# @lynx-template/autolink-device-info

Autolinked Lynx native library that registers `DeviceInfo` on Android and
iOS hosts. Bundles consume it through `@lynx-app/native-bridge#deviceInfo`.

`getInfo` returns a JSON envelope `{ "value": { … } }` (or `{ "error": … }`)
with:

| Field | Android | iOS |
| --- | --- | --- |
| `model` | `Build.MODEL` | `utsname.machine` (e.g. `iPhone17,2`) |
| `manufacturer` | `Build.MANUFACTURER` | `Apple` |
| `osVersion` | `Build.VERSION.RELEASE` | `UIDevice.systemVersion` |
| `osApiLevel` | `Build.VERSION.SDK_INT` | `null` |
| `appVersion` | `PackageInfo.versionName` | `CFBundleShortVersionString` |
| `appBuild` | `PackageInfo` (long) version code | `CFBundleVersion` |
| `density` | `DisplayMetrics.density` | `UIScreen.scale` |
| `locale` | `Locale.getDefault().toLanguageTag()` | `NSLocale.currentLocale.localeIdentifier` |
| `isTablet` | `smallestScreenWidthDp >= 600` | `UIUserInterfaceIdiomPad` |
| `isFoldable` | hinge-angle sensor feature (API 30+) | always `false` |

No permissions are required on either platform.

HarmonyOS ships `DeviceInfoModule` (backed by `deviceInfo`,
`bundleManager` and `display`) as the `harmony/` source HAR, registered
globally by the official HarmonyOS Hvigor Autolink provider.
