# @lynx-template/autolink-websocket

Autolinked Lynx native library that registers `NativeWebSocketModule` on
Android and iOS hosts. Bundles keep consuming the JS API through
`@lynx-template/native-bridge`; the module name and event contract
(`nativeWebSocket` global events) are unchanged from the previous
host-owned implementation.

- **Android** (`android/`) — OkHttp-based transport compiled as a Gradle
  library project and registered by `org.lynxsdk.lynx.library-build`.
- **iOS** (`ios/`) — `NSURLSessionWebSocketTask` transport packaged as the
  `lynx-app-websocket` pod and registered by `cocoapods-lynx-library`.

HarmonyOS hosts are **not** covered by Lynx Autolink and continue to
register their own `NativeWebSocketModule` in
`app/harmonyApp/entry/src/main/ets/native/`.
