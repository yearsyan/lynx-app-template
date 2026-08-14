# Android host

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
- For a real device (USB or network ADB), set
  `lynx.dev.bundle.url=http://<host-LAN-IP>:3000/main.lynx.bundle` in
  `app/androidApp/local.properties`; the property defaults to empty (embedded
  bundle) and the `10.0.2.2` example value only reaches the emulator's host
  loopback. The phone must be on the same LAN as the rspeedy dev server.

## Run the verified workflow

Prefer the repository helper so discovered client and session IDs remain
consistent across build, install, launch, and CDP probes:

```bash
python3 .agent/skills/lynx-native-debug/scripts/debug_android_cdp.py \
  --device '<adb-serial>'
```

Use `--skip-build` or `--skip-install` only after verifying the matching APK
or installed app. Use `--expression '<javascript>'` to replace the default
side-effect-free `6 * 7` probe.

When Gradle cache, ADB, local sockets, or package downloads are sandboxed,
request approval and rerun the same helper. Do not bypass environment controls.
The helper removes only the `CODEX_SANDBOX_NETWORK_DISABLED` marker before
starting `agent-lynx`; it cannot grant network access. It force-stops only the
selected Debug package before launch so an existing Activity cannot retain an
older bundle's HMR WebSocket endpoint.

## Verify native integration before changing it

Inspect:

- `app/androidApp/app/build.gradle.kts`
- `app/androidApp/app/src/debug/java/com/lynxapp/DevToolInitializer.kt`
- `app/androidApp/app/src/main/java/com/lynxapp/LynxTemplateApplication.kt`
- `app/androidApp/app/src/main/java/com/lynxapp/component/LynxViewFactory.kt`
- `app/androidApp/app/src/main/java/com/lynxapp/LynxGenericResourceFetcher.kt`

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

Keep `LynxGenericResourceFetcher` registered on every LynxView builder with
`setEnableGenericResourceFetcher(LynxBooleanOption.TRUE)`. The rspeedy HMR
client loads `*.hot-update.json/js` patches through this fetcher; the fetcher
without the enable flag (or vice versa) makes HMR fail with
"No available provider or fetcher". `LynxWebSocketModule` for the HMR
WebSocket itself comes from the debug-only lynx-devtool dependency.

## Diagnose connection failures

- No client and no listener: inspect device ports `8901-8910`, Debug presets,
  QuickJS bridge loading, and service registration order.
- Listener exists but no client: use direct `agent-lynx --no-daemon`
  transport, verify the selected ADB device, and request network approval when
  required.
- Client exists but no session: wait for `main.lynx.bundle` to load, then
  relaunch and rediscover both IDs.
- Initial bundle loads but HMR repeatedly disconnects: inspect the expanded
  console error object, not just its stack. Compare its WebSocket `url` with the
  active Rspeedy listener. A stale Activity can still retry an endpoint from an
  older bundle even when CDP and the page itself look healthy; use the helper's
  clean package restart and rediscover client/session IDs.
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
Separate verified observations from supported-but-untested features. Verified
on this machine against a USB-connected OnePlus PLC110 (Android 16): client
`<serial>:8901`, session 1 loading `http://<lan-ip>:3000/main.lynx.bundle`
over Wi-Fi, `Runtime.evaluate` → 42, DOM root `#document`. HMR is verified
too: after a clean package restart corrected a stale `:3001` WebSocket from an
older bundle, the server held an established connection to the phone,
`get-console` reported `[HMR] Updated modules` for `./src/App.tsx`, the visible
marker updated, PID `29985` stayed stable, and counter state `1` was preserved.
Applying several hot-updates in rapid succession was observed to
leave overlapping/duplicated UI on this template host; a fresh app start
renders correctly — treat that as a host-level re-render quirk, not an
HMR transport failure.

Official references:

- https://lynxjs.org/4.0/guide/start/integrate-lynx-devtool.html
- https://lynxjs.org/next/api/cdp/api-ref.html
- https://lynxjs.org/next/ai/skills/lynx-devtool.html
