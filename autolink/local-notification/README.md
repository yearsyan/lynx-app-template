# autolink/local-notification

The `LocalNotification` NativeModule: posts local notifications through the
system notification center — immediately or after a `delayMs` delay — and
cancels them by id (`cancelAll` clears everything). Notification permission
prompting lives in the separate `autolink/permissions` module; `notify`
only checks the enablement gate and resolves with `permissionDenied` when
posting would be silently dropped.

The public package owns validation and the Promise facade. Bridge options and
results are structured objects, so this module does not require manual JSON
serialization or parsing.

Platform notes:

- Android: one app-visible channel (`lynx.local`); delayed notifications
  are scheduled through `AlarmManager` and survive process death (exact
  alarms when the platform allows, inexact windows otherwise). Scheduled
  ids are tracked in `SharedPreferences` so `cancelAll` also clears
  pending alarms after a restart.
- iOS: scheduled through `UNNotificationRequest` triggers (max 7 days);
  a center delegate presents notifications as banners while the app is in
  the foreground.
- HarmonyOS: delayed delivery uses in-process timers, so pending delays
  (and `cancelAll` coverage) do not outlive the app process.

- Android: `LocalNotificationModule.java` under `android/src/main/java` (package `com.lynxapp.autolink.localnotification`)
- iOS: `ios/src/LocalNotificationModule.m`
- HarmonyOS: `harmony/src/main/ets/LocalNotificationModule.ets` (source HAR, autolink-registered)
- Raw TypeScript contract: `types/platform-native-module.d.ts`

Keep the three implementations and the contract in sync —
`pnpm native:contracts:check` validates method names and arity.
