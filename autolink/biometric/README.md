# @lynx-template/autolink-biometric

Autolinked Lynx native library that registers `Biometric` on Android, iOS
and HarmonyOS. The package exports a validated `biometric` Promise API for
local authentication and server-verifiable, biometric-gated P-256 signing.

Authentication is policy-based: `biometricWeak`, `biometricStrong`, or
`deviceOwnerAuthentication`. Face versus fingerprint is not caller-selectable;
the system uses whichever enrolled modality satisfies the policy.

Signing v2 supports multiple keys identified by `keyId`:

- `createSigningKey({ scope, attestationChallenge? })`
- `getSigningKey({ keyId })`
- `deleteSigningKey({ keyId })`
- `signChallenge({ keyId, challenge, contextHash, title, reason })`

Each signature covers a versioned domain, `keyId`, the 32-byte operation
context hash, and a 16..64-byte server challenge. Private keys are
non-exportable and signing always requires strong biometrics. Use
`securityLevel` and the optional Android attestation chain as registration
signals; never treat local `authenticate().success` alone as server proof.

- **Android** (`android/`) — `androidx.biometric.BiometricPrompt` compiled
  as a Gradle library project. The prompt is hosted by the current
  `FragmentActivity`, so Lynx page activities must extend
  `FragmentActivity` (`LynxPageActivity` in this template does). The
  library declares `USE_BIOMETRIC` in its manifest.
- **iOS** (`ios/`) — `LocalAuthentication` (`LAContext.evaluatePolicy`)
  packaged as the `lynx-app-biometric` pod. Face ID additionally needs
  `NSFaceIDUsageDescription` in the host's `Info.plist`. Physical devices
  require Secure Enclave for signing keys; simulator builds may use a
  software keychain key.

- **HarmonyOS** (`harmony/`) — `userAuth` plus HUKS, distributed as a source
  HAR and registered by the official Hvigor Autolink provider. It declares
  `ohos.permission.ACCESS_BIOMETRIC`.

See `docs/native-modules.md` in the repository for lifecycle, rotation,
payload layout, and server verification examples.
