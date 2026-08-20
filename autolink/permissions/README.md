# autolink/permissions

The `Permissions` NativeModule: a unified runtime-permission surface for
notifications, camera, photo library and microphone across Android, iOS and
HarmonyOS. `check` reads the current state without UI; `request` shows the
system prompt when needed and resolves with the resulting state (a user
refusal resolves with `denied` instead of rejecting).

The public package wraps the callback-style raw module as Promises. Bridge
arguments and results are structured objects, so this module does not require
manual JSON serialization or parsing.

Statuses normalize to `granted` / `limited` / `denied` / `notDetermined` /
`restricted`. Android cannot distinguish "never asked" from "don't ask
again", so it never reports `notDetermined` and `request` may still prompt
after a `denied` answer; iOS reports `denied` once the user has refused
(system-settings-only afterwards).

Host requirements:

- Android: prompts are hosted by a headless androidx fragment, so the
  LynxView's host activity must be a `FragmentActivity` (the same
  requirement as `autolink/biometric`). The module manifest merges
  `POST_NOTIFICATIONS`, `CAMERA`, `RECORD_AUDIO`, `READ_MEDIA_IMAGES`,
  `READ_MEDIA_VISUAL_USER_SELECTED` and `READ_EXTERNAL_STORAGE` (≤32) into
  the host app while this module is enabled.
- iOS: the host `Info.plist` must declare the matching usage strings
  (`NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription`,
  `NSMicrophoneUsageDescription`); notification authorization needs none.
- HarmonyOS: `ohos.permission.CAMERA`, `MICROPHONE` and `READ_IMAGEVIDEO`
  must be declared in the entry module's `requestPermissions`
  (notification enablement goes through `requestEnableNotification`).

- Android: `android/src/main/java/com/lynxapp/autolink/permissions/PermissionsModule.java`
- iOS: `ios/src/PermissionsModule.m`
- HarmonyOS: `harmony/src/main/ets/PermissionsModule.ets` (source HAR, autolink-registered)
- Raw TypeScript contract: `types/platform-native-module.d.ts`

Keep the three implementations and the contract in sync —
`pnpm native:contracts:check` validates method names and arity.
