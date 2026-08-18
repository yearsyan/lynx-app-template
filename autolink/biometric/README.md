# @lynx-template/autolink-biometric

Autolinked Lynx native library that registers `Biometric` (system
fingerprint / face prompt with optional device-credential fallback) on
Android and iOS hosts. Bundles keep consuming the JS API through
`@lynx-app/native-bridge`.

- **Android** (`android/`) — `androidx.biometric.BiometricPrompt` compiled
  as a Gradle library project. The prompt is hosted by the current
  `FragmentActivity`, so Lynx page activities must extend
  `FragmentActivity` (`LynxPageActivity` in this template does). The
  library declares `USE_BIOMETRIC` in its manifest.
- **iOS** (`ios/`) — `LocalAuthentication` (`LAContext.evaluatePolicy`)
  packaged as the `lynx-app-biometric` pod. Face ID additionally needs
  `NSFaceIDUsageDescription` in the host's `Info.plist`.

HarmonyOS ships the `userAuth`-backed `Biometric` (permission
`ohos.permission.ACCESS_BIOMETRIC`) as the `harmony/` source HAR,
registered globally by the official HarmonyOS Hvigor Autolink provider.
