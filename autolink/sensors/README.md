# @lynx-template/autolink-sensors

Autolinked Lynx native library that registers `Sensors` on Android and iOS
hosts. Bundles consume it through `@lynx-app/native-bridge#sensors`.

`isAvailable`/`start`/`stop` are command methods acked with an error string.
Readings stream back through the Lynx `GlobalEventEmitter` on the `sensors`
event as `{ type, … , timestamp }` payloads:

| Sensor | Payload fields | Android | iOS |
| --- | --- | --- | --- |
| `accelerometer` | `x`, `y`, `z` (m/s², incl. gravity) | `TYPE_ACCELEROMETER` | `CMMotionManager` accelerometer updates |
| `compass` | `heading` (0-360° magnetic), `accuracy` (±°, -1 unreliable) | rotation vector, else accelerometer + magnetometer fusion; remapped to the display rotation | `CLLocationManager` heading updates (`magneticHeading`/`headingAccuracy`) |

Permissions:

- Android — none.
- iOS — compass readings require location authorization
  (`NSLocationWhenInUseUsageDescription` + runtime request, handled by the
  module); denial surfaces as a `compass` error event. The accelerometer and
  Android sensors need nothing.

HarmonyOS hosts are **not** covered by Lynx Autolink and manually register
their `SensorsModule` (backed by `@ohos.sensor` accelerometer/orientation
sensors, which require `ohos.permission.ACCELEROMETER`) from `app/harmonyApp`.
