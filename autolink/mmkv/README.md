# @lynx-template/autolink-mmkv

Autolinked Lynx native library that registers `KV` (MMKV-backed
string storage) on Android and iOS hosts. Bundles consume the JS API through
`@lynx-app/native-bridge`.

- **Android** (`android/`) — depends on `com.tencent:mmkv` and initializes it
  on first module construction, so hosts no longer call
  `MMKV.initialize()` themselves.
- **iOS** (`ios/`) — packaged as the `lynx-app-mmkv` pod and depends on the
  `MMKV` pod.

HarmonyOS hosts are **not** covered by Lynx Autolink and continue to
register their own `KV` in
`app/harmonyApp/entry/src/main/ets/native/`.
