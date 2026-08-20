# @lynx-template/autolink-sensors

Autolinked Lynx native library that registers `Sensors` on Android, iOS and
HarmonyOS hosts. Bundles import `sensors` from this package root.

`isAvailable`/`start`/`stop` are command methods acked with an error string.
Readings stream back through the Lynx `GlobalEventEmitter` on the `sensors`
event as `{ type, … , timestamp }` payloads:

| Sensor | Payload fields | Android | iOS | HarmonyOS |
| --- | --- | --- | --- | --- |
| `accelerometer` | `x`, `y`, `z` (m/s², incl. gravity) | `TYPE_ACCELEROMETER` | `CMMotionManager` accelerometer updates | `sensor.on(ACCELEROMETER)` |
| `compass` | `heading` (0-360° magnetic), `accuracy` (±°, -1 unreliable) | rotation vector, else accelerometer + magnetometer fusion; remapped to the display rotation | `CLLocationManager` heading updates (`magneticHeading`/`headingAccuracy`) | `sensor.on(ORIENTATION)` |

Permissions:

- Android — none.
- iOS — compass readings require location authorization
  (`NSLocationWhenInUseUsageDescription` + runtime request, handled by the
  module); denial surfaces as a `compass` error event. The accelerometer and
  Android sensors need nothing.
- HarmonyOS — accelerometer requires `ohos.permission.ACCELEROMETER`; compass
  requires no permission.

The HarmonyOS source HAR is registered by the official Hvigor Autolink
registry. Each Lynx module instance owns its listeners and a `LynxViewClient`
removes only those callbacks when the page or template runtime is destroyed.
