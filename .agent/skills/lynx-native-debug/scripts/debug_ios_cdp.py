#!/usr/bin/env python3
"""Build, install, launch, and verify this repository's iOS Lynx Debug host."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import selectors
import shlex
import subprocess
import sys
import time
from typing import Any
from urllib.parse import urlparse


REPO_ROOT = Path(__file__).resolve().parents[4]
IOS_DIR = REPO_ROOT / "app" / "iosApp"
APP_PATH = (
    IOS_DIR
    / "build"
    / "sim"
    / "Build"
    / "Products"
    / "Debug-iphonesimulator"
    / "iosApp.app"
)
DEVICE_APP_PATH = (
    IOS_DIR
    / "build"
    / "device"
    / "Build"
    / "Products"
    / "Debug-iphoneos"
    / "iosApp.app"
)

DEVTOOL_MARKER = re.compile(r"invokeMethod: LynxWebSocketModule\.connect")
DEV_URL_MARKER = re.compile(r"url:\S*main\.lynx\.bundle")
HMR_URL_MARKER = re.compile(
    r"LynxWebSocketModule\.connect\s*,\s*args:\s*(ws://\S+)"
)
HMR_FAILURE_MARKER = re.compile(
    r"websocketFailed|\[rspeedy-dev-server\]\s+Disconnected!"
)


class WorkflowError(RuntimeError):
    pass


def endpoint(url: str) -> tuple[str | None, int | None]:
    parsed = urlparse(url)
    port = parsed.port
    if port is None:
        port = 443 if parsed.scheme in {"https", "wss"} else 80
    return parsed.hostname, port


def hmr_markers(text: str, dev_url: str) -> dict[str, Any]:
    websocket_urls = HMR_URL_MARKER.findall(text)
    websocket_url = websocket_urls[-1] if websocket_urls else None
    endpoint_matches = (
        websocket_url is not None and endpoint(websocket_url) == endpoint(dev_url)
    )
    connection_failed = bool(HMR_FAILURE_MARKER.search(text))
    return {
        "devtool_module_invoked": bool(DEVTOOL_MARKER.search(text)),
        "dev_bundle_loaded": bool(DEV_URL_MARKER.search(text)),
        "hmr_websocket_url": websocket_url,
        "hmr_websocket_matches_dev_url": endpoint_matches,
        "hmr_websocket_failed": connection_failed,
        "hmr_websocket_ready": endpoint_matches and not connection_failed,
    }


def load_application_id() -> str:
    # iOS uses package.json#nativeApp.bundleId directly (no debug suffix);
    # scripts/apply_native_config.mjs keeps PRODUCT_BUNDLE_IDENTIFIER in sync.
    package_file = REPO_ROOT / "package.json"
    try:
        package_data = json.loads(package_file.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise WorkflowError(f"cannot read {package_file}: {error}") from error
    native_app = package_data.get("nativeApp")
    bundle_id = (native_app or {}).get("bundleId") if isinstance(native_app, dict) else None
    override = ((native_app or {}).get("ios") or {}).get("bundleId") if isinstance(native_app, dict) else None
    bundle_id = override or bundle_id
    if not isinstance(bundle_id, str) or not bundle_id:
        raise WorkflowError("package.json#nativeApp.bundleId must be a non-empty string")
    return bundle_id


def run(
    command: list[str],
    *,
    capture: bool = False,
    env: dict[str, str] | None = None,
    check: bool = True,
) -> str:
    print(f"+ {shlex.join(command)}", flush=True)
    result = subprocess.run(
        command,
        text=True,
        capture_output=capture,
        check=False,
        env=env,
    )
    if check and result.returncode != 0:
        details = "\n".join(
            part.strip()
            for part in (result.stdout, result.stderr)
            if part and part.strip()
        )
        raise WorkflowError(
            f"command failed with exit code {result.returncode}:\n{details}"
        )
    return (result.stdout or "").strip() if capture else ""


def simctl(*arguments: str, capture: bool = False, check: bool = True) -> str:
    return run(["xcrun", "simctl", *arguments], capture=capture, check=check)


def pick_simulator(requested: str | None) -> str:
    if requested:
        return requested
    output = simctl("list", "devices", "booted", capture=True)
    for line in output.splitlines()[1:]:
        if "(" in line and "Booted" in line:
            return line.split("(")[1].split(")")[0]
    raise WorkflowError(
        "no booted simulator; boot one or pass --simulator 'iPhone 17 Pro'"
    )


def launch_with_console(
    simulator: str,
    bundle_id: str,
    dev_url: str,
    seconds: float,
) -> tuple[list[str], int]:
    """Follow app stdout; terminating this process also stops the app."""
    env = dict(os.environ)
    env["SIMCTL_CHILD_LYNX_DEV_BUNDLE_URL"] = dev_url
    process = subprocess.Popen(
        ["xcrun", "simctl", "launch", "--console-pty", simulator, bundle_id],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        env=env,
    )
    lines: list[str] = []
    selector = selectors.DefaultSelector()
    assert process.stdout is not None
    selector.register(process.stdout, selectors.EVENT_READ)
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        events = selector.select(timeout=max(0.1, deadline - time.monotonic()))
        if not events:
            continue
        line = process.stdout.readline()
        if not line:
            break
        lines.append(line.rstrip())
        print(line.rstrip(), flush=True)
    selector.close()
    pid = process.pid
    process.terminate()
    # --console-pty follows the app; terminating it also stops the app.
    return lines, pid


CDP_PROBE_SCRIPT = """
const m = await import('@lynx-js/devtool-connector');
const t = await import('@lynx-js/devtool-connector/transport');
const connector = new m.Connector([new t.DesktopTransport()]);
const clients = await connector.listClients();
const client = clients.find((c) => c.info?.bundleId === process.argv[1]);
if (!client) throw new Error('client not found on localhost DebugRouter ports');
// list-sessions may come back empty on this DebugRouter build; the template
// session is conventionally id 1, so fall back to probing it directly.
let lynx = null;
for (let attempt = 0; attempt < 3 && !lynx; attempt++) {
  const reply = await connector.sendListSessionMessage(client.id);
  const sessions = reply?.data?.data || reply?.data || [];
  lynx = (Array.isArray(sessions) ? sessions : []).find((s) => s.type === 'lynx');
  if (!lynx) await new Promise((r) => setTimeout(r, 1000));
}
if (!lynx) lynx = { session_id: 1, type: 'lynx', url: '(probed)' };
const result = await connector.sendCDPMessage(
  client.id, lynx.session_id, 'Runtime.evaluate',
  { expression: '6 * 7', returnByValue: true });
if (result?.result?.value !== 42) throw new Error('unexpected evaluate result: ' + JSON.stringify(result));
console.log(JSON.stringify({
  client: client.id,
  info: client.info,
  session: lynx,
  evaluate: result?.result ?? null,
}));
"""


def detect_lan_ip() -> str | None:
    for interface in ("en0", "en1"):
        result = subprocess.run(
            ["ipconfig", "getifaddr", interface],
            text=True,
            capture_output=True,
            check=False,
        )
        address = result.stdout.strip()
        if result.returncode == 0 and address:
            return address
    return None


def detect_team_id() -> str:
    # Prefer the Xcode account-backed team (it can create/repair signing
    # assets via -allowProvisioningUpdates); a keychain 'Apple Development'
    # certificate may belong to a personal team that has no Xcode account.
    plist = Path.home() / "Library/Preferences/com.apple.dt.Xcode.plist"
    result = subprocess.run(
        ["plutil", "-extract", "IDEProvisioningTeamByIdentifier", "xml1", "-o", "-", str(plist)],
        text=True,
        capture_output=True,
        check=False,
    )
    match = re.search(
        r"<key>teamID</key>\s*<string>([A-Z0-9]{10})</string>", result.stdout
    )
    if match:
        return match.group(1)
    output = run(
        ["security", "find-identity", "-v", "-p", "codesigning"],
        capture=True,
    )
    match = re.search(r"Apple Development:.*?\(([A-Z0-9]{10})\)", output)
    if not match:
        raise WorkflowError(
            "no 'Apple Development' signing identity found; pass --team-id"
        )
    return match.group(1)


def devicectl(*arguments: str, capture: bool = False, check: bool = True) -> str:
    return run(["xcrun", "devicectl", *arguments], capture=capture, check=check)


def resolve_device(requested: str) -> dict[str, Any]:
    """Resolve a devicectl device by UDID, coredevice identifier, or name."""
    import tempfile

    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as handle:
        json_path = handle.name
    devicectl("list", "devices", "--json-output", json_path)
    try:
        payload = json.loads(Path(json_path).read_text(encoding="utf-8"))
    finally:
        Path(json_path).unlink(missing_ok=True)
    devices = payload.get("result", {}).get("devices", [])

    def label(device: dict[str, Any]) -> str:
        props = device.get("deviceProperties", {})
        hardware = device.get("hardwareProperties", {})
        return (
            f"{props.get('name')} "
            f"(udid={hardware.get('udid')}, id={device.get('identifier')})"
        )

    lowered = requested.lower()
    matches = [
        device
        for device in devices
        if requested
        in {
            device.get("identifier"),
            device.get("hardwareProperties", {}).get("udid"),
            device.get("deviceProperties", {}).get("name"),
        }
        or device.get("deviceProperties", {}).get("name", "").lower() == lowered
    ]
    if not matches:
        raise WorkflowError(
            f"no paired devicectl device matches {requested!r}; "
            f"available: {[label(d) for d in devices]}"
        )
    device = matches[0]
    pairing = device.get("connectionProperties", {}).get("pairingState")
    if pairing and pairing != "paired":
        raise WorkflowError(f"device {label(device)} is not paired: {pairing}")
    return device


def terminate_device_app(device_id: str, bundle_id: str) -> None:
    """Best-effort terminate; devicectl process terminate requires --pid."""
    import tempfile

    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as handle:
        json_path = handle.name
    subprocess.run(
        [
            "xcrun",
            "devicectl",
            "device",
            "info",
            "processes",
            "--device",
            device_id,
            "--json-output",
            json_path,
        ],
        text=True,
        capture_output=True,
        check=False,
    )
    try:
        payload = json.loads(Path(json_path).read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        Path(json_path).unlink(missing_ok=True)
        return
    Path(json_path).unlink(missing_ok=True)

    def walk(node: Any) -> None:
        if isinstance(node, dict):
            identifiers = str(
                node.get("bundleIdentifier")
                or node.get("bundleID")
                or ""
            )
            pid = node.get("processIdentifier") or node.get("pid")
            if identifiers == bundle_id and pid is not None:
                devicectl(
                    "device",
                    "process",
                    "terminate",
                    "--device",
                    device_id,
                    "--pid",
                    str(pid),
                    check=False,
                )
            for value in node.values():
                walk(value)
        elif isinstance(node, list):
            for value in node:
                walk(value)

    walk(payload)


def launch_device_with_console(
    device_id: str,
    bundle_id: str,
    dev_url: str,
    seconds: float,
) -> list[str]:
    """Launch on a real device and follow console output; terminating the
    devicectl process forwards the signal to the app."""
    environment = json.dumps({"LYNX_DEV_BUNDLE_URL": dev_url})
    process = subprocess.Popen(
        [
            "xcrun",
            "devicectl",
            "device",
            "process",
            "launch",
            "--console",
            "--terminate-existing",
            "--device",
            device_id,
            "--environment-variables",
            environment,
            bundle_id,
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    lines: list[str] = []
    selector = selectors.DefaultSelector()
    assert process.stdout is not None
    selector.register(process.stdout, selectors.EVENT_READ)
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        events = selector.select(timeout=max(0.1, deadline - time.monotonic()))
        if not events:
            continue
        line = process.stdout.readline()
        if not line:
            break
        lines.append(line.rstrip())
        print(line.rstrip(), flush=True)
    selector.close()
    process.terminate()
    return lines


def launch_device_detached(device_id: str, bundle_id: str, dev_url: str) -> None:
    """Relaunch without --console so the app stays alive for CDP probing."""
    environment = json.dumps({"LYNX_DEV_BUNDLE_URL": dev_url})
    devicectl(
        "device",
        "process",
        "launch",
        "--terminate-existing",
        "--device",
        device_id,
        "--environment-variables",
        environment,
        bundle_id,
        capture=True,
    )


def agent_environment() -> dict[str, str]:
    env = dict(os.environ)
    env.pop("CODEX_SANDBOX_NETWORK_DISABLED", None)
    env["AGENT_LYNX_DISABLE_UPDATE_NOTICE"] = "1"
    return env


def agent_lynx(arguments: list[str], env: dict[str, str]) -> str:
    return run(
        ["npx", "--yes", "agent-lynx", *arguments, "--no-daemon"],
        env=env,
        capture=True,
    )


def parse_json(output: str, label: str) -> Any:
    try:
        return json.loads(output)
    except json.JSONDecodeError as error:
        raise WorkflowError(f"{label} did not return JSON:\n{output}") from error


def device_cdp_probe(
    bundle_id: str,
    bundle: str,
    device_name: str,
    expression: str,
) -> dict[str, Any]:
    """Probe CDP on a USB real device through the agent-lynx iOS usbmux
    transport (the transport that enumerates physical devices only)."""
    env = agent_environment()
    client: dict[str, Any] | None = None
    for attempt in range(1, 9):
        clients = parse_json(agent_lynx(["list-clients"], env), "list-clients")
        # Exact match only: a substring test would also match other apps on
        # other transports (e.g. the Android sibling com.lynxapp.debug).
        matches = [
            candidate
            for candidate in clients
            if (candidate.get("info") or {}).get("AppProcessName") == bundle_id
            or (candidate.get("info") or {}).get("bundleId") == bundle_id
        ]
        if matches:
            client = matches[0]
            break
        if attempt < 8:
            time.sleep(1)
    if client is None:
        raise WorkflowError(
            f"no DebugRouter client for {bundle_id} on {device_name}; "
            "the stock agent-lynx iOS transport only enumerates usbmux "
            "devices, so check pairing and the app's DebugRouter listener; "
            f"last list-clients output: {json.dumps(clients, ensure_ascii=False)}"
        )
    client_id = str(client["id"])

    session: dict[str, Any] | None = None
    for attempt in range(1, 9):
        sessions = parse_json(
            agent_lynx(["list-sessions", "--client", client_id], env),
            "list-sessions",
        )
        matches = [
            candidate
            for candidate in sessions
            if candidate.get("type") == "lynx"
            and str(candidate.get("url", "")).endswith(f"/{bundle}")
        ]
        if matches:
            session = matches[0]
            break
        if attempt < 9:
            time.sleep(1)
    if session is None:
        # list-sessions may come back empty on this DebugRouter build even
        # when a page is live; the template session is conventionally id 1.
        session = {"session_id": 1, "type": "lynx", "url": "(probed)"}
    session_id = str(session["session_id"])

    evaluation = parse_json(
        agent_lynx(
            [
                "cdp",
                "--client",
                client_id,
                "--session",
                session_id,
                "--method",
                "Runtime.evaluate",
                json.dumps(
                    {"expression": expression, "returnByValue": True},
                    separators=(",", ":"),
                ),
            ],
            env,
        ),
        "Runtime.evaluate",
    )
    document = parse_json(
        agent_lynx(
            [
                "cdp",
                "--client",
                client_id,
                "--session",
                session_id,
                "--method",
                "DOM.getDocument",
                json.dumps({"depth": 2}, separators=(",", ":")),
            ],
            env,
        ),
        "DOM.getDocument",
    )
    return {
        "client": client,
        "session": session,
        "runtime_evaluate": evaluation,
        "dom_root": document.get("root", {}),
    }


def find_connector_dir() -> Path | None:
    """Locate a node_modules directory holding @lynx-js/devtool-connector."""
    pattern = os.path.expanduser(
        "~/.npm/_npx/*/node_modules/@lynx-js/devtool-connector"
    )
    for hit in sorted(Path(p) for p in __import__("glob").glob(pattern)):
        if hit.is_dir():
            return hit.parent
    return None


def cdp_probe(bundle_id: str) -> dict[str, Any] | None:
    """Probe CDP over the simulator app's localhost DebugRouter port."""
    connector_dir = find_connector_dir()
    if connector_dir is None:
        print(
            "cdp probe skipped: @lynx-js/devtool-connector not found in the "
            "npx cache (run any `npx agent-lynx` command once to populate it)",
            file=sys.stderr,
        )
        return None
    result = subprocess.run(
        [
            "node",
            "--input-type=module",
            "-e",
            CDP_PROBE_SCRIPT,
            "--",
            bundle_id,
        ],
        text=True,
        capture_output=True,
        check=False,
        cwd=str(connector_dir),
    )
    if result.returncode != 0:
        print(f"cdp probe failed: {result.stderr.strip()}", file=sys.stderr)
        return None
    try:
        return json.loads(result.stdout.strip().splitlines()[-1])
    except (json.JSONDecodeError, IndexError):
        return None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--simulator", help="simulator name, such as 'iPhone 17 Pro'")
    parser.add_argument(
        "--device",
        help="paired real device UDID, coredevice identifier, or name "
        "(devicectl); builds Debug-iphoneos and probes CDP over the "
        "agent-lynx iOS usbmux transport",
    )
    parser.add_argument(
        "--team-id",
        help="Apple Development team ID for device signing "
        "(default: auto-detect from the codesigning identity)",
    )
    parser.add_argument(
        "--expression",
        default="6 * 7",
        help="side-effect-free JavaScript probe for the device CDP round-trip",
    )
    parser.add_argument(
        "--bundle",
        default="main.lynx.bundle",
        help="target Lynx bundle name for session matching",
    )
    parser.add_argument(
        "--dev-url",
        default="http://localhost:3000/main.lynx.bundle",
        help="rspeedy dev server URL (rspeedy listens on 0.0.0.0:3000 by default)",
    )
    parser.add_argument("--skip-build", action="store_true", help="reuse the existing app")
    parser.add_argument("--skip-install", action="store_true", help="skip simctl install")
    parser.add_argument(
        "--console-seconds",
        type=float,
        default=8.0,
        help="how long to follow app stdout for verification markers",
    )
    parser.add_argument(
        "--cdp-probe",
        action="store_true",
        help="also probe CDP (Runtime.evaluate) over the app's localhost "
        "DebugRouter TCP port (8901+)",
    )
    args = parser.parse_args()

    try:
        bundle_id = load_application_id()
        if args.device:
            return run_device_workflow(args, bundle_id)
        simulator = pick_simulator(args.simulator)
        simctl("bootstatus", simulator, "-b")

        if not args.skip_build:
            run(
                [
                    "xcodebuild",
                    "-workspace",
                    str(IOS_DIR / "iosApp.xcworkspace"),
                    "-scheme",
                    "iosApp",
                    "-configuration",
                    "Debug",
                    "-destination",
                    f"platform=iOS Simulator,name={simulator}",
                    "-derivedDataPath",
                    str(IOS_DIR / "build" / "sim"),
                    "build",
                ]
            )
        if not APP_PATH.is_dir():
            raise WorkflowError(f"Debug app does not exist: {APP_PATH}")
        if not args.skip_install:
            simctl("install", simulator, str(APP_PATH))

        simctl("terminate", simulator, bundle_id, check=False)
        lines, _ = launch_with_console(
            simulator,
            bundle_id,
            args.dev_url,
            args.console_seconds,
        )
        text = "\n".join(lines)
        markers = hmr_markers(text, args.dev_url)
        probe = None
        if args.cdp_probe:
            # Relaunch detached (same shape as the verified manual path) and
            # probe CDP over the app's localhost DebugRouter port.
            simctl("terminate", simulator, bundle_id, check=False)
            env = dict(os.environ)
            env["SIMCTL_CHILD_LYNX_DEV_BUNDLE_URL"] = args.dev_url
            subprocess.run(
                ["xcrun", "simctl", "launch", simulator, bundle_id],
                check=False,
                capture_output=True,
                env=env,
            )
            time.sleep(6)
            probe = cdp_probe(bundle_id)
            simctl("terminate", simulator, bundle_id, check=False)

        summary: dict[str, Any] = {
            "simulator": simulator,
            "app": str(APP_PATH),
            "app_bytes": sum(
                p.stat().st_size for p in APP_PATH.rglob("*") if p.is_file()
            ),
            "bundle_id": bundle_id,
            "dev_url": args.dev_url,
            "markers": markers,
            "cdp_probe": probe,
        }
        if not markers["devtool_module_invoked"]:
            summary["warning"] = (
                "LynxWebSocketModule.connect not observed in console output; "
                "check AppDelegate DevTool flags (lynxDebugEnabled and "
                "devtoolEnabled must both be true in Debug) and that the "
                "LynxDevtool/BaseDevtool/DebugRouter pods are installed"
            )
        if not markers["hmr_websocket_ready"]:
            summary.setdefault("warning", "")
            summary["warning"] += (
                ";" if summary["warning"] else ""
            ) + (
                " HMR WebSocket was not ready; keep one Rspeedy instance and "
                "verify that its host and port match the development bundle URL"
            )
        if probe is None and args.cdp_probe:
            summary.setdefault("warning", "")
            summary["warning"] += (
                ";" if summary["warning"] else ""
            ) + " CDP probe failed; check the DebugRouter TCP listener on ports 8901+"
        print(json.dumps(summary, ensure_ascii=False, indent=2))
        if not markers["dev_bundle_loaded"]:
            return 1
        if not markers["hmr_websocket_ready"]:
            return 3
        if args.cdp_probe and probe is None:
            return 2
        return 0
    except (OSError, WorkflowError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


def run_device_workflow(args: argparse.Namespace, bundle_id: str) -> int:
    device = resolve_device(args.device)
    # xcodebuild destinations and devicectl both accept the hardware UDID
    # (00008130-...); the coredevice identifier (4C6B5EE9-...) works for
    # devicectl only, so prefer the UDID everywhere.
    hardware = device.get("hardwareProperties", {})
    device_id = str(hardware.get("udid") or device["identifier"])
    props = device.get("deviceProperties", {})
    device_name = str(props.get("name", device_id))

    dev_url = args.dev_url
    if dev_url == "http://localhost:3000/main.lynx.bundle":
        # localhost only reaches a simulator; a real device needs the LAN IP.
        lan_ip = detect_lan_ip()
        if lan_ip is None:
            raise WorkflowError(
                "cannot detect the LAN IP; pass --dev-url explicitly"
            )
        dev_url = f"http://{lan_ip}:3000/main.lynx.bundle"

    if not args.skip_build:
        team_id = args.team_id or detect_team_id()
        run(
            [
                "xcodebuild",
                "-workspace",
                str(IOS_DIR / "iosApp.xcworkspace"),
                "-scheme",
                "iosApp",
                "-configuration",
                "Debug",
                "-destination",
                f"platform=iOS,id={device_id}",
                "-derivedDataPath",
                str(IOS_DIR / "build" / "device"),
                f"DEVELOPMENT_TEAM={team_id}",
                "-allowProvisioningUpdates",
                "build",
            ]
        )
    if not DEVICE_APP_PATH.is_dir():
        raise WorkflowError(f"Debug device app does not exist: {DEVICE_APP_PATH}")
    if not args.skip_install:
        devicectl(
            "device",
            "install",
            "app",
            "--device",
            device_id,
            str(DEVICE_APP_PATH),
        )

    lines = launch_device_with_console(
        device_id,
        bundle_id,
        dev_url,
        args.console_seconds,
    )
    text = "\n".join(lines)
    markers = hmr_markers(text, dev_url)

    probe = None
    if args.cdp_probe:
        # Terminating the devicectl --console process stops the app (signals
        # are forwarded), so relaunch detached before probing CDP.
        launch_device_detached(device_id, bundle_id, dev_url)
        time.sleep(6)
        probe = device_cdp_probe(
            bundle_id,
            args.bundle,
            device_name,
            args.expression,
        )
        terminate_device_app(device_id, bundle_id)

    summary: dict[str, Any] = {
        "device": {
            "identifier": device_id,
            "name": device_name,
            "model": device.get("hardwareProperties", {}).get("modelCode"),
            "os_version": props.get("osVersionNumber"),
            "developer_mode": props.get("developerModeStatus"),
            "transport": device.get("connectionProperties", {}).get(
                "transportType"
            ),
        },
        "app": str(DEVICE_APP_PATH),
        "app_bytes": sum(
            p.stat().st_size for p in DEVICE_APP_PATH.rglob("*") if p.is_file()
        ),
        "bundle_id": bundle_id,
        "dev_url": dev_url,
        "markers": markers,
        "cdp_probe": probe,
    }
    warnings: list[str] = []
    if not markers["devtool_module_invoked"]:
        warnings.append(
            "LynxWebSocketModule.connect not observed in console output; "
            "devicectl --console may not carry os_log lines on a real "
            "device, so treat the CDP probe as the authoritative check"
        )
    if not markers["dev_bundle_loaded"]:
        warnings.append(
            "dev bundle URL not observed in console output; check "
            "LYNX_DEV_BUNDLE_URL and that the device can reach the dev "
            "server over LAN"
        )
    if not markers["hmr_websocket_ready"]:
        warnings.append(
            "HMR WebSocket was not ready; keep one Rspeedy instance and "
            "verify that its host and port match the development bundle URL"
        )
    if warnings:
        summary["warning"] = "; ".join(warnings)
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    if args.cdp_probe:
        if probe is None:
            return 2
        return 0 if markers["hmr_websocket_ready"] else 3
    if not markers["dev_bundle_loaded"]:
        return 1
    return 0 if markers["hmr_websocket_ready"] else 3


if __name__ == "__main__":
    raise SystemExit(main())
