# @lynx-template/autolink-mmkv

Autolinked Lynx native library that registers `NativeKVModule` (MMKV-backed
string storage) on Android and iOS hosts. Bundles keep consuming the JS API
through `@lynx-template/native-bridge`; the module name is unchanged from the
previous host-owned implementation.

- **Android** (`android/`) — depends on `com.tencent:mmkv` and initializes it
  on first module construction, so hosts no longer call
  `MMKV.initialize()` themselves.
- **iOS** (`ios/`) — packaged as the `lynx-app-mmkv` pod and depends on the
  `MMKV` pod.

HarmonyOS hosts are **not** covered by Lynx Autolink and continue to
register their own `NativeKVModule` in
`app/harmonyApp/entry/src/main/ets/native/`.
