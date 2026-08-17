# @lynx-template/autolink-clipboard

Autolinked Lynx native library that registers `Clipboard`
(plain-text system clipboard) on Android and iOS hosts. Bundles keep
consuming the JS API through `@lynx-app/native-bridge`.

- **Android** (`android/`) — `ClipboardManager` transport compiled as a
  Gradle library project and registered by `org.lynxsdk.lynx.library-build`.
- **iOS** (`ios/`) — `UIPasteboard` transport packaged as the
  `lynx-app-clipboard` pod and registered by `cocoapods-lynx-library`.

HarmonyOS hosts are **not** covered by Lynx Autolink and manually register
their Pasteboard-backed `Clipboard` from `app/harmonyApp`.
