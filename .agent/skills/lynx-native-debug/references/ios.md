# iOS and iPadOS host

Validate this repository's iOS host and hand established runtime targets to
`$lynx-devtool` for further inspection.

## Preserve repository invariants

- Resolve the repository root from this Skill instead of assuming a checkout
  path.
- Build `app/iosApp` and target `main.lynx.bundle` unless the user names
  another bundle.
- Derive the app bundle ID from `package.json#nativeApp` (`bundleId`, optional
  `ios.bundleId` override). Unlike Android there is no debug suffix.
- Keep the Lynx DevTool integration Debug-only: `LynxDevtool`, `BaseDevtool`,
  and `DebugRouter` pods use `:configurations => ['Debug']`, and the
  AppDelegate wiring is wrapped in `#if DEBUG`. Release builds must stay
  link-clean of DevTool classes.
- DevTool needs BOTH `LynxEnv` flags in Debug: `lynxDebugEnabled` (registers
  the devtool modules, including `LynxWebSocketModule` for the rspeedy HMR
  client) and `devtoolEnabled`. Either one alone is not enough.
- Keep `LynxGenericResourceFetcher` registered on every LynxView builder with
  `enableGenericResourceFetcher = .true`; HMR hot-update patches load through
  it and the DevTool pods do not provide one.

## Run the verified workflow

Start the dev server first (`pnpm dev:main`), then prefer the repository
helper so the build, install, launch, and marker checks stay consistent:

```bash
python3 .agent/skills/lynx-native-debug/scripts/debug_ios_cdp.py \
  --simulator 'iPhone 17 Pro' --cdp-probe
```

For a paired USB real device (verified on an iPad mini A17 Pro, iPadOS 26.6):

```bash
python3 .agent/skills/lynx-native-debug/scripts/debug_ios_cdp.py \
  --device '<udid-or-name>' --cdp-probe
```

The device path builds `Debug-iphoneos`, installs and launches via
`devicectl` (`--terminate-existing`, `LYNX_DEV_BUNDLE_URL` passed through
`--environment-variables`), and probes CDP through the stock `agent-lynx`
iOS usbmux transport. `--dev-url` defaults to the host LAN IP on port 3000
for devices (localhost only reaches simulators). Signing uses Automatic
with `DEVELOPMENT_TEAM` auto-detected from the Xcode account-backed team
(`IDEProvisioningTeamByIdentifier` in the Xcode preferences), falling back
to the keychain `Apple Development` certificate's team; pass `--team-id`
to override. A keychain certificate alone is not enough — the team must
have an Xcode account or `-allowProvisioningUpdates` cannot create
profiles. xcodebuild destinations need the hardware UDID
(`00008130-...`), not the devicectl coredevice identifier; the helper
maps between them.

Use `--skip-build` or `--skip-install` only after verifying the matching app
already exists on the target. The helper follows app stdout (via
`simctl launch --console-pty` or `devicectl process launch --console`, both
of which carry the app's NSLog/stderr lines) and reports whether the dev
bundle was loaded and whether the official `LynxWebSocketModule.connect`
ran. It also requires the HMR WebSocket host and port to match the development
bundle URL and rejects observed connection failures; invocation alone is not
proof that HMR is connected. With `--cdp-probe` it additionally performs a
real CDP round-trip (`Runtime.evaluate` → 42).

The dev URL comes from the `LYNX_DEV_BUNDLE_URL` environment variable. For
the in-app DEV panel (UserDefaults `lynx.debug.bundle-servers`) remember that
simulator `cfprefsd` caches app defaults: write the plist only while the app
is terminated, or relaunch with `xcrun simctl terminate` first.

## Know the transport limits (verified on this machine)

- The simulator app's DebugRouter listens on plain TCP (ports 8901+, bound
  when `enableAllSessions` runs). The simulator shares the host network, so
  CDP works by connecting to `127.0.0.1:8901` directly — use
  `@lynx-js/devtool-connector`'s `DesktopTransport` (peertalk-encoded TCP),
  as the skill helper does with `--cdp-probe`. The stock
  `agent-lynx list-clients` CLI does not list simulator apps this way; its
  iOS transport enumerates usbmux devices only.
- `list-sessions` may come back empty on this DebugRouter build even when a
  page is live; the template session is conventionally id 1 — probe it
  directly instead of relying on the listing.
- The ordering of `AppDelegate` initialization is load-bearing:
  `LynxEnv.sharedInstance()` must run BEFORE any
  `LynxServices.getInstanceWith` lookup. LynxEnv init drives the LynxService
  lazy-load registry scan; querying first returns nil and the DebugRouter
  TCP listener never starts (HMR still works because that path does not need
  the service).
- USB-connected real devices are reachable through the stock `agent-lynx`
  iOS transport (usbmux/peertalk) — verified on this machine against an
  iPad mini (A17 Pro) over wired USB: client `<udid>:8901` with
  `info.bundleId == 'com.lynxapp'`, session 1, `Runtime.evaluate` → 42.
  Match clients by exact `info.bundleId`/`info.AppProcessName`; a substring
  match also hits sibling apps on other transports (the Android Debug
  build `com.lynxapp.debug`).
- First launch after a fresh real-device install shows the iOS Local
  Network permission prompt; until granted, the dev bundle fetch fails
  with `error_code 102/10203` "The Internet connection appears to be
  offline." Grant it on the device and relaunch.
- On iPadOS the DebugRouter client info reports `deviceModel: "iPhone"`;
  do not use it to identify the device class.
- HMR is verified end-to-end on the USB real device: a source edit makes
  rspeedy emit `main.<hash>.hot-update.json/js`, the app fetches them over
  LAN through `LynxGenericResourceFetcher`, and QuickJS evaluates the patch
  (~8s after save) while the `rsbuild-hmr` WebSocket
  (`ws://<lan-ip>:3000/rsbuild-hmr`) stays connected. The console line to
  look for: `App::EvaluateScript: http://<lan-ip>:3000/main.<hash>.hot-update.js`.
  The simulator loads the dev bundle over plain LAN sockets the same way,
  independent of the CDP transport.
- When the device locks, iOS backgrounds and suspends the app: CDP
  evaluate aborts, screencast frames stop (`take-screenshot` times out),
  and `list-clients` may transiently return empty. Unlock the device,
  relaunch with devicectl, and retry — the tunnel recovers on its own
  (`devicectl list devices` shows `connected` again).
- The `rsbuild-hmr` WebSocket token is deterministic across dev server
  restarts, so a stale bundle from an older server can keep a mismatched
  port/token; when in doubt, relaunch the app against a freshly started
  dev server. The helper now rejects that mismatch instead of treating a
  `LynxWebSocketModule.connect` invocation alone as success. A coordinated
  real-device run then reported `[HMR] Updated modules` for `./src/App.tsx`,
  updated the visible marker, and kept process PID `1368` stable.

## Verify native integration before changing it

Inspect:

- `app/iosApp/Podfile` (Devtool subspec + Debug-only pods)
- `app/iosApp/iosApp/AppDelegate.swift` (`#if DEBUG` DevTool service block)
- `app/iosApp/iosApp/LynxGenericResourceFetcher.h/.m`
- `app/iosApp/iosApp/ViewControllers/LynxPageViewController.swift` (fetcher
  registration on the LynxView builder)

Keep the service bootstrap in this shape and order (LynxEnv first):

```swift
// LynxEnv init drives the LynxService lazy-load scan; it must run before
// any LynxServices.getInstanceWith lookup or the registry is still empty.
let lynxEnv = LynxEnv.sharedInstance()
#if DEBUG
let devTool = LynxServices.getInstanceWith(
  LynxServiceDevToolProtocol.self
) as? LynxServiceDevToolProtocol
devTool?.enableAllSessions()
devTool?.lynxDebugPresetValue = true
devTool?.logBoxPresetValue = true
lynxEnv.lynxDebugEnabled = true
lynxEnv.devtoolEnabled = true
lynxEnv.logBoxEnabled = true
#endif
```

If the Release build fails to link with missing `DebugRouter` symbols, the
Debug-only `:configurations` scoping is incomplete — transitive pod
`BaseDevtool` must be scoped too.

## Report evidence

Report the simulator or device, the .app path and size, install status, the
dev URL, the console markers (`dev_bundle_loaded`, `devtool_module_invoked`,
`hmr_websocket_url`, `hmr_websocket_ready`), and the CDP probe result (client
id, session, `Runtime.evaluate` output).
Separate verified observations from supported-but-untested features (simulator
CDP and USB real-device CDP have both been exercised on this machine).

Official references:

- https://lynxjs.org/4.0/guide/start/integrate-lynx-devtool.html
- https://lynxjs.org/next/ai/skills/lynx-devtool.html
