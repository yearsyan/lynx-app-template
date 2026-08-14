# HarmonyOS and OpenHarmony host

Validate this repository's HarmonyOS host on a real device. Keep observed HMR
results separate from HarmonyOS CDP or DebugRouter claims; this workflow does
not establish those transports.

## Preserve repository and device state

- Resolve the repository root from this Skill instead of assuming a checkout
  path.
- Build `app/harmonyApp` and serve `main.lynx.bundle` unless the user names
  another bundle.
- Derive the bundle name from `package.json#nativeApp.harmony.bundleName` and
  resolve the launch ability from the module manifest; do not hard-code either
  when the project configuration differs.
- Select the exact HDC serial requested by the user. If multiple devices are
  connected and none was selected, stop and show the choices.
- Preserve pre-existing worktree changes. Snapshot every file changed for a
  test marker or local signing, then restore only those exact edits.
- Treat DevEco signing paths and encrypted passwords as local secrets. Never
  quote them in a report, add them to the template, or leave them in a diff.
- Do not uninstall the app, clear its data, clear device logs, or touch another
  attached device unless the user asks.

## Establish the device and network

Prefer `hdc` from `PATH`; on the standard macOS DevEco installation, fall back
to:

```bash
HDC=/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc
"$HDC" list targets -v
"$HDC" -t '<serial>' shell bm get -u
"$HDC" -t '<serial>' shell ifconfig wlan0
```

Record the model, HarmonyOS version, device UDID, connection type, and WLAN
address. Derive the Mac's active LAN address from `ifconfig` and verify that it
is reachable from the phone. A physical device must use the Mac LAN address,
not `localhost`.

Start the server and record the actual URL printed by Rspeedy; port 3000 may
already be occupied:

```bash
pnpm dev:main
```

Use the emitted `http://<host>:<port>/main.lynx.bundle`. Do not rely only on HDC
reverse forwarding: the served development bundle also contains the HMR
WebSocket host, which must be reachable from the device. Confirm that
`bundle/main/lynx.config.ts` does not disable `dev.hmr` and that
`bundle/main/src/index.tsx` accepts hot updates.

## Build and install a signed Debug HAP

Use the repository's DevEco/Hvigor versions. A standard macOS command is:

```bash
NODE_HOME=/Applications/DevEco-Studio.app/Contents/tools/node \
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw \
  assembleHap --mode module \
  -p product=default -p module=entry@debug -p buildMode=debug --no-daemon
```

Install only the signed output:

```bash
"$HDC" -t '<serial>' install -r \
  '<repo>/app/harmonyApp/entry/build/default/outputs/debug/entry-debug-signed.hap'
"$HDC" -t '<serial>' shell aa start \
  -a '<entry-ability>' -b '<bundle-name>'
```

If Hvigor produces only `entry-debug-unsigned.hap` or warns that no
`signingConfig` exists:

1. Open `app/harmonyApp` in DevEco Studio.
2. In Project Structure > Signing Configs, enable automatic debug signing.
3. Verify that the generated debug profile contains the UDID returned by
   `bm get -u`.
4. Link the `default` product to the generated signing config, rebuild, and
   confirm that `SignHap` runs.
5. Restore the temporary `build-profile.json5` change after the test if the
   file was clean before the workflow.

An unsigned install failing with `no signature file` is expected and is not an
HMR failure. A signed install rejection usually means that the provisioning
profile does not include the selected device.

## Configure the in-app DEV override

In the Debug app, open the floating `DEV` entry and set Bundle servers to:

```text
main=http://<host-LAN-IP>:<actual-port>
```

Then choose `Save & reload`. The mapping is device-local and Debug-only. For
HDC-driven UI automation, use `uitest dumpLayout` and
`snapshot_display` to locate controls by text and bounds; never reuse
coordinates from another device or orientation.

Confirm that the page now reflects the development bundle before editing any
source. If it still shows the embedded bundle, inspect the saved mapping,
bundle ID, build mode, and server URL.

## Prove HMR instead of a reinstall

Use an observable, reversible test:

1. Record the app PID with `pidof <bundle-name>` and capture a baseline
   screenshot.
2. Put the page into visible state, such as incrementing the template counter.
3. Use `apply_patch` to add a unique visible marker to
   `bundle/main/src/App.tsx`.
4. Observe Rspeedy report `building src/App.tsx` followed by `ready built`.
5. Capture the updated device screen without touching Reload, DEV, or the app
   launcher.
6. Read the PID again. Require the marker to change and the PID to remain
   identical. Prefer the visible state to remain unchanged as evidence that
   HMR, rather than full live reload, applied the module update.
7. Restore the source marker exactly and let the server compile the restoration.

If the marker changes but component state resets, report the result as live
reload fallback or inconclusive HMR rather than overstating it. If the initial
development bundle loads but no update arrives, inspect all three paths:

- HMR WebSocket connectivity from the device to the emitted host and port.
- `LynxGenericResourceFetcher` registration for `*.hot-update.json/js`.
- `LynxWebSocketModule` registration and the hot-accept block in `index.tsx`.

Also inspect the Rspeedy log and device `hilog` for connection, patch-fetch,
or provider errors.

## Clean up and report evidence

- Choose `Clear overrides & reload` in the DEV page.
- Stop only the Rspeedy process started by this workflow.
- Restore the marker and temporary signing association; verify both have no
  diff. Leave all unrelated user changes intact.
- Leave the test app installed unless the user requests removal.

Report the exact target model and OS, signed HAP path, install result, host and
device LAN addresses, actual dev URL, incremental build time, PID before and
after, preserved state, screenshot paths, and cleanup status. Separate facts
observed on the selected device from capabilities inferred from configuration.

Verified on this repository with a USB-connected HUAWEI Pura X (VDE-AL00),
HarmonyOS `6.1.0.135(SP8C00E120R3P7)`: the device loaded the LAN-served bundle,
Rspeedy rebuilt `src/App.tsx` in 0.20 seconds, `hilog` recorded both
`main.<hash>.hot-update.json` and `.hot-update.js`, the visible marker updated,
and app PID `3827` remained stable. The device-local Bundle servers override
was empty again after cleanup. Counter state preservation was not established,
so future workflows should still include it when the input path is available.

Official references:

- https://lynxjs.org/guide/start/integrate-with-existing-apps?platform=harmony
- https://lynxjs.org/api/rspeedy/rspeedy.dev.hmr
- https://lynxjs.org/rspeedy/cli
