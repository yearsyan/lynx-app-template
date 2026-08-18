# @lynx-template/autolink-websocket

Autolinked Lynx native library that registers `WebSocket` on
Android and iOS hosts. Bundles keep consuming the JS API through
`@lynx-app/native-bridge`; events use the `webSocket` global channel.

- **Android** (`android/`) — OkHttp-based transport compiled as a Gradle
  library project and registered by `org.lynxsdk.lynx.library-build`.
- **iOS** (`ios/`) — `NSURLSessionWebSocketTask` transport packaged as the
  `lynx-app-websocket` pod and registered by `cocoapods-lynx-library`.

The HarmonyOS implementation owns a per-page connection controller and is
therefore registered explicitly rather than through a global provider in
`app/harmonyApp/entry/src/main/ets/native/`.
