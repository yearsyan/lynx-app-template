# @lynx-template/autolink-mmkv

Autolinked Lynx native library that registers `KV` (MMKV-backed
string storage) on Android and iOS hosts. Bundles consume the JS API through
`@lynx-app/native-bridge`.

- **Android** (`android/`) — depends on `com.tencent:mmkv` and initializes it
  on first module construction, so hosts no longer call
  `MMKV.initialize()` themselves.
- **iOS** (`ios/`) — packaged as the `lynx-app-mmkv` pod, depends on the
  `MMKV` pod, and performs MMKV's required main-thread bootstrap on first
  module construction.

HarmonyOS ships its `@tencent/mmkv`-backed `KV` as the `harmony/` source
HAR (ohpm dependency included), registered globally by the official
HarmonyOS Hvigor Autolink provider.
