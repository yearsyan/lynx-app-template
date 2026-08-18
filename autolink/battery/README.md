# @lynx-template/autolink-battery

Autolinked Lynx native library that registers `Battery` on Android and iOS
hosts. Bundles consume it through `@lynx-app/native-bridge#battery`.

`getInfo` returns a JSON envelope `{ "value": { … } }` (or `{ "error": … }`)
with:

| Field | Android | iOS |
| --- | --- | --- |
| `level` | `ACTION_BATTERY_CHANGED` level/scale (0..1) | `UIDevice.batteryLevel` (0..1, `null` on simulator) |
| `charging` | status is `CHARGING` or `FULL` | state is `charging` or `full` |

No permissions are required on either platform. iOS values become readable
after enabling `UIDevice.batteryMonitoringEnabled`, which the module does on
demand.

HarmonyOS ships the `@ohos.batteryInfo`-backed `BatteryModule` as the
`harmony/` source HAR, registered globally by the official HarmonyOS Hvigor
Autolink provider.
