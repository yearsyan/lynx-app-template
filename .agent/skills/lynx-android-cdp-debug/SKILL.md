---
name: lynx-android-cdp-debug
description: Build, install, launch, and validate this repository's Android Lynx Debug host and its DebugRouter/CDP integration. Use for the Android Debug APK, native DevTool setup, a missing agent-lynx client or session, ports 8901-8910, QuickJS or V8 packaging checks, or a one-shot Android smoke test. For runtime inspection after a client and session are available, use lynx-devtool instead.
---

# Lynx Android CDP Debug

Validate this repository's Android host and hand established runtime targets to
`$lynx-devtool` for further inspection.

## Preserve repository invariants

- Resolve the repository root from this Skill instead of assuming a checkout
  path.
- Build `app/androidApp` and target `main.lynx.bundle` unless the user names
  another bundle.
- Derive the Debug application ID from `package.json#nativeApp`; do not assume
  it equals the Kotlin namespace.
- Resolve the installed launcher activity through Android's package manager.
- Keep DevTool dependencies and initialization in the Debug variant only.
- Load the QuickJS bridge, exclude the V8 bridge/runtime, and package only
  `arm64-v8a`.
- Select the exact ADB serial requested by the user. If multiple devices are
  online and none was selected, stop and show the choices.

## Run the verified workflow

Prefer the repository helper so discovered client and session IDs remain
consistent across build, install, launch, and CDP probes:

```bash
python3 .agent/skills/lynx-android-cdp-debug/scripts/debug_android_cdp.py \
  --device '<adb-serial>'
```

Use `--skip-build` or `--skip-install` only after verifying the matching APK
or installed app. Use `--expression '<javascript>'` to replace the default
side-effect-free `6 * 7` probe.

When Gradle cache, ADB, local sockets, or package downloads are sandboxed,
request approval and rerun the same helper. Do not bypass environment controls.
The helper removes only the `CODEX_SANDBOX_NETWORK_DISABLED` marker before
starting `agent-lynx`; it cannot grant network access.

## Verify native integration before changing it

Inspect:

- `app/androidApp/app/build.gradle.kts`
- `app/androidApp/app/src/debug/java/com/lynxapp/DevToolInitializer.kt`
- `app/androidApp/app/src/main/java/com/lynxapp/LynxTemplateApplication.kt`

Keep `lynx-devtool` dependencies as `debugImplementation`, exclude `v8so`,
and initialize the service before `LynxEnv.init`:

```kotlin
val service = LynxDevToolService.INSTANCE
service.enableAllSessions()
LynxServiceCenter.inst().registerService(service)
service.setLynxDebugPresetValue(true)
service.setLogBoxPresetValue(true)
service.setLoadQJSBridge(true)
service.setLoadV8Bridge(false)
```

Retain `enableLynxDebug(BuildConfig.DEBUG)`,
`enableDevtool(BuildConfig.DEBUG)`, and `enableLogBox(BuildConfig.DEBUG)`.
Never move `DevToolInitializer` into `src/main`.

## Diagnose connection failures

- No client and no listener: inspect device ports `8901-8910`, Debug presets,
  QuickJS bridge loading, and service registration order.
- Listener exists but no client: use direct `agent-lynx --no-daemon`
  transport, verify the selected ADB device, and request network approval when
  required.
- Client exists but no session: wait for `main.lynx.bundle` to load, then
  relaunch and rediscover both IDs.
- Runtime or Debugger failure: confirm
  `liblynxdevtool_qjs_bridge.so` exists in the Debug APK and select the
  appropriate main or background VM thread.
- Wrong client: match the URL-encoded ADB serial and `AppProcessName`, never
  list order.
- Release includes DevTool or V8: inspect source sets, dependency
  configurations, ABI filters, and APK contents; do not infer from size alone.

Do not clear logcat, uninstall the app, or touch another attached device unless
the user asks.

## Continue with runtime inspection

Pass the exact client and session returned by the helper to `$lynx-devtool`
for DOM, console, screenshot, interaction, trace, memory, or ReactLynx work.
Avoid duplicating those generic command workflows here.

## Report evidence

Report the ADB target, APK absolute path and byte/MiB size, build and install
status, DebugRouter port, client metadata, bundle session, Runtime result, DOM
root, parsed business script, and whether a V8-named native library exists.
Separate verified observations from supported-but-untested features.

Official references:

- https://lynxjs.org/4.0/guide/start/integrate-lynx-devtool.html
- https://lynxjs.org/next/api/cdp/api-ref.html
- https://lynxjs.org/next/ai/skills/lynx-devtool.html
