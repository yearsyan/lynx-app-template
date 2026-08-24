# @lynx-template/autolink-app-installer

Privileged, opt-in application-update hand-off for Lynx hosts. This package is
intentionally disabled in the template's default Autolink selection.

## API

```ts
import { appInstaller } from '@lynx-template/autolink-app-installer';

const capabilities = await appInstaller.getCapabilities();
if (!capabilities.permissionGranted) {
  await appInstaller.openPermissionSettings();
  // Re-check after the app becomes active again.
}

const result = await appInstaller.launchInstall({
  uri: downloadedTask.fileUri,
  expectedPackageName: 'com.example.enterprise',
  expectedVersionCode: 42,
  expectedSha256: manifest.sha256,
});
// result.status === 'launched'; installation has not yet been confirmed.
```

Android copies the source into `cache/LynxFiles/updates`, with a 1 GiB limit,
then verifies all of the following before checking installer permission or
opening system UI:

- the complete APK SHA-256 equals `expectedSha256`;
- the archive package equals both `expectedPackageName` and the running app;
- the archive version code equals the expected value and is newer;
- the APK signer matches the installed app (including a valid forward signing
  rotation lineage).

Only that narrow staging directory is exposed through the package's
FileProvider. `openPermissionSettings()` is separate and settles as soon as the
settings page opens. `launchInstall()` returns `status: 'launched'` when the
system installer starts, not when installation finishes.

iOS and HarmonyOS report `supported: false` and reject the two mutating calls;
use their store/update channels instead.

## Distribution policy

Enabling this package merges Android's `REQUEST_INSTALL_PACKAGES` permission
into the host. Google Play restricts that permission, so Play-distributed apps
should leave this module disabled and use Play In-App Updates. It is intended
for managed enterprise or direct/sideload distribution whose policy permits
self-update.

To opt in, add `app-installer` to
`package.json#nativeApp.autolinkModules`, then run:

```sh
pnpm native:autolink:apply
pnpm install
```

`AppInstaller` is permanently excluded from the WebView module bridge even
when the native package is enabled.
