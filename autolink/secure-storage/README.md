# @lynx-template/autolink-secure-storage

Autolinked Lynx native module exporting `SecureStorage`: get / set / remove of
small secret strings.

- **Android** — values are sealed with an AES-256-GCM key that lives in
  AndroidKeyStore and never leaves it; only the random IV and ciphertext are
  persisted in the app's private `SharedPreferences`.
- **iOS** — values are stored as Keychain generic-password items
  (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`).

HarmonyOS ships its HUKS-backed implementation as the `harmony/` source
HAR, registered globally by the official HarmonyOS Hvigor Autolink provider.

The raw method signatures are defined in `types/platform-native-module.d.ts`.
`contracts/native-modules.json` maps that declaration to the native
implementations, and `src/index.ts` is generated from the mapping.

## Usage

```ts
import { secureStorage } from '@lynx-app/native-bridge';
```
