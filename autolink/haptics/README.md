# @lynx-template/autolink-haptics

Autolinked Lynx native library that registers `Haptics`
(one-shot impact haptics, light / medium / heavy) on Android and iOS hosts.
Bundles import `haptics` from this package root.

- **Android** (`android/`) — `Vibrator` transport compiled as a Gradle
  library project and registered by `org.lynxsdk.lynx.library-build`. The
  library manifest contributes the `VIBRATE` permission via manifest
  merger, so hosts no longer need to declare it themselves.
- **iOS** (`ios/`) — `UIImpactFeedbackGenerator` transport packaged as the
  `lynx-app-haptics` pod and registered by `cocoapods-lynx-library`.

HarmonyOS ships the Vibrator-backed `Haptics` as the `harmony/` source HAR,
registered globally by the official HarmonyOS Hvigor Autolink provider.
