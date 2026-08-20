# @lynx-template/autolink-device-info

Autolinked Lynx native library that registers one `DeviceInfo` module on
Android, iOS and HarmonyOS. It owns device facts, current safe-area reads,
first-frame/reactive safe-area host adapters and status-bar foreground style.

Bundles import these package-root facades:

```ts
import {
  deviceInfo,
  readSafeAreaInsets,
  safeArea,
  statusBar,
} from '@lynx-template/autolink-device-info';

const info = await deviceInfo.getInfo();
const currentInsets = await safeArea.getInsets();
await statusBar.setStyle('dark-content');
```

`getInfo` returns a JSON envelope `{ "value": { … } }` (or `{ "error": … }`)
with:

| Field | Android | iOS | HarmonyOS |
| --- | --- | --- | --- |
| `model` | `Build.MODEL` | `utsname.machine` | `deviceInfo.productModel` |
| `manufacturer` | `Build.MANUFACTURER` | `Apple` | `deviceInfo.brand` |
| `osVersion` | `Build.VERSION.RELEASE` | `UIDevice.systemVersion` | `deviceInfo.osFullName` |
| `osApiLevel` | `Build.VERSION.SDK_INT` | `null` | `deviceInfo.sdkApiVersion` |
| `appVersion` / `appBuild` | `PackageInfo` | bundle info dictionary | `bundleManager` |
| `density` | `DisplayMetrics.density` | `UIScreen.scale` | `display.densityPixels` |
| `locale` | default locale | current locale | system locale |
| `isTablet` / `isFoldable` | configuration / hinge feature | idiom / `false` | device type / display API |

Safe-area values use Lynx logical px (Android dp, iOS pt, HarmonyOS vp). The
package also exports the small native host adapters needed to inject real
geometry before the first render and update it when the window changes.

Status-bar styles are `dark-content` and `light-content`; the background stays
transparent so Lynx continues drawing edge-to-edge. No permission is required.
