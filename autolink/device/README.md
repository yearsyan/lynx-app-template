# @lynx-template/autolink-device

Autolinked device, display, battery and sensors APIs for Lynx hosts
(Android, iOS & HarmonyOS). Exports one Lynx NativeModule, `Device`:

| Method | JS facade |
| --- | --- |
| `getInfo(callback)` | `deviceInfo.getInfo(): Promise<DeviceInfo>` |
| `getSafeAreaInsets(callback)` | `safeArea.getInsets(): Promise<SafeAreaInsets>` |
| `setStatusBarStyle(style, callback)` | `statusBar.setStyle(style): Promise<void>` |
| `screenWidth(callback)` | `display.screenWidth(): Promise<number>` |
| `windowWidth(callback)` | `display.windowWidth(): Promise<number>` |
| `lynxViewWidth(callback)` | `display.lynxViewWidth(): Promise<number>` |
| `getBrightness(callback)` | `display.getBrightness(): Promise<number>` |
| `setBrightness(value, callback)` | `display.setBrightness(value): Promise<void>` |
| `setKeepScreenOn(enabled, callback)` | `display.setKeepScreenOn(enabled): Promise<void>` |
| `openAppSettings(callback)` | `appSettings.open(): Promise<void>` |
| `getBatteryInfo(callback)` | `battery.getInfo(): Promise<BatteryInfo>` |
| `isAvailable(type, callback)` | `sensors.available(type): Promise<boolean>` |
| `start(type, callback)` / `stop(type, callback)` | `sensors.observe(...)` refcounting (internal) |

Notes:

- All widths are Lynx logical pixels (dp/pt/vp) — the unit Lynx layout
  consumes. Geometry is read on demand so configuration changes are
  reflected without a restart.
- Battery reads the sticky broadcast / on-demand APIs; no permission is
  needed and `level` is `null` when the host cannot read it.
- `DeviceInfo.bundleId` is the application id (Android `packageName`, iOS
  bundle identifier, HarmonyOS `bundleName`), so Android debug builds
  report the `.debug` suffixed id.
- `appSettings.open()` jumps to this app's page in the system Settings
  app — the canonical follow-up after a permission was denied. It is the
  only settings destination reachable through public APIs on all three
  platforms (Android `ACTION_APPLICATION_DETAILS_SETTINGS`, iOS
  `UIApplicationOpenSettingsURLString`, HarmonyOS settings'
  `application_info_entry`).
- Sensor readings stream back as `sensors` global events; the JS facade
  keeps each sensor registered only while at least one observer is
  attached. Accelerometer reports m/s^2 including gravity and gyroscope
  rad/s; magnetometer reports the raw geomagnetic field in microtesla and
  barometer the ambient pressure in hectopascals (iOS reports kPa and
  converts; HarmonyOS already reports hPa); compass reports magnetic azimuth 0-360 with an
  accuracy estimate (-1 = unreliable). HarmonyOS additionally needs the
  system-granted `ohos.permission.GYROSCOPE` (declared by the host), and
  iOS compass needs location authorization. Core Motion use also requires
  `NSMotionUsageDescription` in the iOS host.

APK installation deliberately lives in the separate, default-disabled
`@lynx-template/autolink-app-installer` package so Device never contributes
the policy-sensitive Android install permission.

## Host integration

- Safe area, resolved system appearance, and app locale are injected as
  first-frame/reactive init data (`nativeEnvironment`). Read them with
  `readSafeAreaInsets(useInitData())`, `readColorScheme(...)`, and
  `readAppLocale(...)`; the `InitData` augmentation lives in this package.
- Android host helpers: `DeviceSystemUI` (edge-to-edge + status bar) and
  `NativeEnvironmentBridge` (insets → TemplateData/LynxUpdateMeta).
- iOS host helpers: `LynxDeviceTemplateData(insets, additionalData)` and the
  `LynxDeviceStatusBarHost` protocol (see `LynxPageViewController.swift`).
- HarmonyOS host helpers: `NativeSafeAreaController`,
  `NativeStatusBarController` and the page-scoped `DeviceRegistration`
  adapter passed as the module constructor param (see `pages/Index.ets`).
