#!/usr/bin/env python3
"""Build, install, launch, and verify this repository's Android Lynx CDP path."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import time
from typing import Any
from urllib.parse import quote


REPO_ROOT = Path(__file__).resolve().parents[4]
ANDROID_DIR = REPO_ROOT / "app" / "androidApp"
APK_PATH = ANDROID_DIR / "app" / "build" / "outputs" / "apk" / "debug" / "app-debug.apk"


class WorkflowError(RuntimeError):
    pass


def load_debug_application_id() -> str:
    sys.path.insert(0, str(REPO_ROOT))
    try:
        from scripts.apply_native_config import NativeConfigError, load_native_config
    except ImportError as error:
        raise WorkflowError(f"cannot load native configuration helper: {error}") from error
    try:
        return load_native_config().android_debug_application_id
    except (NativeConfigError, OSError) as error:
        raise WorkflowError(f"cannot resolve Android Debug applicationId: {error}") from error


def run(
    command: list[str],
    *,
    cwd: Path | None = None,
    env: dict[str, str] | None = None,
    capture: bool = False,
) -> str:
    print(f"+ {shlex.join(command)}", flush=True)
    result = subprocess.run(
        command,
        cwd=cwd,
        env=env,
        text=True,
        capture_output=capture,
        check=False,
    )
    if result.returncode != 0:
        details = "\n".join(part.strip() for part in (result.stdout, result.stderr) if part.strip())
        raise WorkflowError(f"command failed with exit code {result.returncode}:\n{details}")
    if capture and result.stderr.strip():
        print(result.stderr.rstrip(), file=sys.stderr)
    return result.stdout.strip() if capture else ""


def find_adb() -> str:
    for variable in ("ANDROID_HOME", "ANDROID_SDK_ROOT"):
        sdk_root = os.environ.get(variable)
        if sdk_root:
            candidate = Path(sdk_root) / "platform-tools" / "adb"
            if candidate.is_file():
                return str(candidate)
    adb = shutil.which("adb")
    if adb:
        return adb
    raise WorkflowError("adb was not found; set ANDROID_HOME/ANDROID_SDK_ROOT or add adb to PATH")


def select_device(adb: str, requested: str | None) -> str:
    output = run([adb, "devices", "-l"], capture=True)
    devices = [
        fields[0]
        for line in output.splitlines()[1:]
        if len(fields := line.split()) >= 2 and fields[1] == "device"
    ]
    if requested:
        if requested not in devices:
            raise WorkflowError(f"requested device {requested!r} is not online; online devices: {devices}")
        return requested
    if len(devices) == 1:
        return devices[0]
    if not devices:
        raise WorkflowError("no online ADB device was found")
    raise WorkflowError(f"multiple ADB devices are online; pass --device with one of: {devices}")


def resolve_launcher_component(adb: str, device: str, package_name: str) -> str:
    output = run(
        [
            adb,
            "-s",
            device,
            "shell",
            "cmd",
            "package",
            "resolve-activity",
            "--brief",
            package_name,
        ],
        capture=True,
    )
    for line in reversed(output.splitlines()):
        candidate = line.strip()
        if re.fullmatch(r"[A-Za-z0-9._]+/[A-Za-z0-9._$]+", candidate):
            return candidate
    raise WorkflowError(
        f"cannot resolve the launcher activity for installed package {package_name}"
    )


def agent_environment() -> dict[str, str]:
    env = os.environ.copy()
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


def discover_client(
    device: str,
    package_name: str,
    env: dict[str, str],
) -> dict[str, Any]:
    prefix = f"{quote(device, safe='')}:"
    for attempt in range(1, 6):
        clients = parse_json(agent_lynx(["list-clients"], env), "list-clients")
        matches = [
            client
            for client in clients
            if str(client.get("id", "")).startswith(prefix)
            and client.get("info", {}).get("AppProcessName") == package_name
        ]
        if matches:
            return matches[0]
        if attempt < 5:
            time.sleep(1)
    raise WorkflowError(
        f"no DebugRouter client for {package_name} on {device}; check device ports 8901-8910"
    )


def discover_session(client_id: str, bundle_url: str, env: dict[str, str]) -> dict[str, Any]:
    for attempt in range(1, 6):
        sessions = parse_json(
            agent_lynx(["list-sessions", "--client", client_id], env),
            "list-sessions",
        )
        matches = [
            session
            for session in sessions
            if session.get("type") == "lynx" and session.get("url") == bundle_url
        ]
        if matches:
            return matches[0]
        if attempt < 5:
            time.sleep(1)
    raise WorkflowError(f"client {client_id} has no Lynx session for {bundle_url!r}")


def cdp(
    client_id: str,
    session_id: str,
    method: str,
    params: dict[str, Any],
    env: dict[str, str],
) -> Any:
    output = agent_lynx(
        [
            "cdp",
            "--client",
            client_id,
            "--session",
            session_id,
            "--method",
            method,
            json.dumps(params, separators=(",", ":")),
        ],
        env,
    )
    return parse_json(output, method)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", help="exact ADB serial, such as 192.168.9.127:10000")
    parser.add_argument("--bundle", default="main.lynx.bundle", help="target Lynx session URL")
    parser.add_argument("--expression", default="6 * 7", help="side-effect-free JavaScript probe")
    parser.add_argument("--skip-build", action="store_true", help="reuse the existing Debug APK")
    parser.add_argument("--skip-install", action="store_true", help="reuse the installed Debug app")
    args = parser.parse_args()

    try:
        package_name = load_debug_application_id()
        adb = find_adb()
        device = select_device(adb, args.device)

        if not args.skip_build:
            run([str(ANDROID_DIR / "gradlew"), ":app:assembleDebug"], cwd=ANDROID_DIR)
        if not APK_PATH.is_file():
            raise WorkflowError(f"Debug APK does not exist: {APK_PATH}")

        if not args.skip_install:
            run([adb, "-s", device, "install", "-r", str(APK_PATH)])
        launcher_component = resolve_launcher_component(adb, device, package_name)
        run(
            [
                adb,
                "-s",
                device,
                "shell",
                "am",
                "start",
                "-W",
                "-n",
                launcher_component,
            ]
        )

        env = agent_environment()
        client = discover_client(device, package_name, env)
        client_id = str(client["id"])
        session = discover_session(client_id, args.bundle, env)
        session_id = str(session["session_id"])

        evaluation = cdp(
            client_id,
            session_id,
            "Runtime.evaluate",
            {"expression": args.expression, "returnByValue": True},
            env,
        )
        document = cdp(
            client_id,
            session_id,
            "DOM.getDocument",
            {"depth": 2},
            env,
        )
        sources = parse_json(
            agent_lynx(
                ["get-sources", "--client", client_id, "--session", session_id],
                env,
            ),
            "get-sources",
        )

        summary = {
            "device": device,
            "apk": str(APK_PATH),
            "apk_bytes": APK_PATH.stat().st_size,
            "package": package_name,
            "launcher_component": launcher_component,
            "client": client,
            "session": session,
            "runtime_evaluate": evaluation,
            "dom_root": document.get("root", {}),
            "sources": sources,
        }
        print(json.dumps(summary, ensure_ascii=False, indent=2))
        return 0
    except (OSError, WorkflowError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
