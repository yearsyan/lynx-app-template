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
| `getBatteryInfo(callback)` | `battery.getInfo(): Promise<BatteryInfo>` |
| `isAvailable(type, callback)` | `sensors.available(type): Promise<boolean>` |
| `start(type, callback)` / `stop(type, callback)` | `sensors.observe(...)` refcounting (internal) |

Notes:

- All widths are Lynx logical pixels (dp/pt/vp) — the unit Lynx layout
  consumes. Geometry is read on demand so configuration changes are
  reflected without a restart.
- Battery reads the sticky broadcast / on-demand APIs; no permission is
  needed and `level` is `null` when the host cannot read it.
- Sensor readings stream back as `sensors` global events; the JS facade
  keeps each sensor registered only while at least one observer is
  attached. Accelerometer reports m/s^2 including gravity; compass reports
  magnetic azimuth 0-360 with an accuracy estimate (-1 = unreliable).

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
