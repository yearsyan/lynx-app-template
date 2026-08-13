# HarmonyOS host

ArkTS Stage-model host based on the official Lynx 4.0 integration reference.

For interactive development, build the `debug` target and use the `DEV` button
in the app. It stores an API server and per-bundle development server mappings
on the device. `BundleConfig.ets` remains the fallback for a fixed main-bundle
development URL and the OTA endpoint.

The `debug` and `release` targets use different ArkTS source roots. Only the
Debug root contains the settings page, MMKV keys, validation, and URL resolver;
the Release root contains inert replacements.

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
