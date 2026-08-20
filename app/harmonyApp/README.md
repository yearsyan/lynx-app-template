# HarmonyOS host

ArkTS Stage-model host based on the official Lynx 4.0 integration reference.

For interactive development, build the `debug` target and use the `DEV` button
in the app. It stores per-bundle development server mappings on the device and
offers previously loaded bundle IDs when adding a mapping. `BundleConfig.ets`
remains the fallback for a fixed main-bundle development URL and the OTA
endpoint.

The development settings live in `src/main` (the bundle repository is shared
by both build modes); every read and write is guarded by `BuildProfile.DEBUG`,
so release builds never observe debug values.

For command-line builds, use the Node runtime bundled with DevEco Studio. Newer
system Node releases can be incompatible with the bundled hvigor plugin:

```bash
NODE_HOME=/Applications/DevEco-Studio.app/Contents/tools/node \
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw \
  assembleHap --mode module -p product=default -p module=entry@release \
  -p buildMode=release --no-daemon
```

Use `entry@debug` together with `-p buildMode=debug` for a Debug HAP.

NativeModule libraries are discovered from workspace `lynx.lib.json` files by
the official Lynx Hvigor Autolink plugin. The generated Registry HAR installs
all package-owned modules app-wide. `Index.ets` forwards ArkUI's discrete Back
event to the package-owned route controller, attaches the `DeviceInfo` page
adapters (safe area and status-bar route state), and injects both Back and
Router registrations through `LynxContext.contextData`.
