---
name: lynx-native-debug
description: Build, install, launch, and validate this repository's native Lynx Debug hosts on Android, iOS, and HarmonyOS/OpenHarmony, including real-device or simulator selection, signing, LAN-served Rspeedy bundles, HMR, Debug-only DevTool integration, DebugRouter discovery, and supported CDP smoke probes. Use for one platform or coordinated three-platform debugging, missing native clients or sessions, HMR failures, hot-update fetch or WebSocket failures, or proof that the same source edit updates connected native devices. For generic inspection after a client and session exist, use lynx-devtool instead.
---

# Lynx Native Debug

Validate the native host boundary, then hand established runtime targets to
`$lynx-devtool`. Keep build, signing, transport, and HMR setup here; do not
duplicate generic DOM, console, screenshot, trace, or component workflows.

## Route by platform

Read every selected platform reference completely before acting:

- Android: [references/android.md](references/android.md)
- iOS or iPadOS: [references/ios.md](references/ios.md)
- HarmonyOS or OpenHarmony: [references/harmony.md](references/harmony.md)

For a multi-platform request, read all applicable references and use one
shared Rspeedy server. Preserve platform-specific evidence rather than reducing
the result to a single aggregate pass/fail.

## Preserve shared invariants

- Resolve the repository root from this Skill; never assume a checkout path.
- Derive identifiers from `package.json#nativeApp` and platform manifests.
- Select exact ADB, CoreDevice/simulator, and HDC targets. If the requested
  platform has multiple plausible devices and the user did not select one,
  stop and show the choices.
- Use Debug builds. Keep DevTool code and dependencies out of Release builds.
- Serve `main.lynx.bundle` unless the user requests another bundle.
- Before starting Rspeedy, inspect existing listeners and their process working
  directories. Keep exactly one dev server for a bundle workspace. Two Rspeedy
  instances sharing the same output can make a bundle served on one port embed
  the other instance's HMR WebSocket port.
- Record the URL printed by `pnpm dev:main`; never assume port 3000 remains
  available. Physical devices must reach the Mac LAN address used inside the
  bundle's HMR WebSocket configuration; `localhost` reaches only the device.
- Preserve pre-existing worktree and device state. Snapshot any local signing,
  development-URL, or visible-marker edits and restore only those exact edits.
- Do not clear logs or app data, uninstall apps, or touch unselected devices
  unless the user asks.

## Run the host workflow

1. Inspect the dirty worktree and enumerate each platform's devices.
2. Start `pnpm dev:main` once and capture its actual bundle URL and log.
3. Follow the selected platform reference to build, sign, install, and launch.
   Prefer the bundled Android and iOS helpers where applicable:

```bash
python3 .agent/skills/lynx-native-debug/scripts/debug_android_cdp.py \
  --device 'ADB_SERIAL'

python3 .agent/skills/lynx-native-debug/scripts/debug_ios_cdp.py \
  --device 'IOS_UDID_OR_NAME' --cdp-probe
```

4. Confirm that each host loaded the LAN-served development bundle before
   editing source. Android and iOS should also complete their supported CDP
   round trip when requested.
5. Keep exact client and session IDs for `$lynx-devtool`; refresh them after an
   app restart or page replacement.

Use `--skip-build` or `--skip-install` only after verifying that the existing
artifact or installed app matches the current source and target. When caches,
devices, local sockets, signing, or package downloads are sandboxed, request
approval and rerun the same workflow rather than bypassing controls.

## Prove HMR across requested hosts

Use one reversible edit so all connected hosts receive the same update:

1. Capture a baseline screen or DOM marker for every host. Put the page into
   visible state, such as incrementing the template counter.
2. Record stable host identity: Android/HarmonyOS PID and iOS process or
   DebugRouter client/session identity.
3. Use `apply_patch` to add a unique visible marker to
   `bundle/main/src/App.tsx`.
4. Observe one Rspeedy incremental build, then verify the marker on every host
   without touching Reload, DEV, or an app launcher.
5. Require host identity to remain stable. Prefer visible component state to
   remain unchanged; a reset makes HMR inconclusive and may indicate live
   reload fallback.
6. Restore the source marker exactly and observe the restoration compile.

If the initial bundle loads but a patch does not, inspect the HMR WebSocket,
the platform's generic resource fetcher for `*.hot-update.json/js`, and the
hot-accept block in `bundle/main/src/index.tsx`. Report a platform failure
without masking passes on the other hosts.

## Clean up and report

- Clear only development overrides created by this workflow.
- Stop only the Rspeedy process started by this workflow.
- Restore marker, signing, and local URL edits, then verify their scoped diffs.
- Leave test apps installed unless the user requests removal.

Report each platform's selected target, OS, artifact path and size, build and
install status, actual dev URL, HMR evidence, identity before and after, state
preservation, CDP result where supported, artifact paths, and cleanup status.
Separate observed results from supported-but-untested capabilities.
