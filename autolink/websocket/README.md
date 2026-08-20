# @lynx-template/autolink-websocket

Autolinked Lynx native library that registers `WebSocket` on Android, iOS and
HarmonyOS hosts. Its root exports the `WebSocketConnection`/`webSocket` API;
events use the `webSocket` global channel.

- **Android** (`android/`) — OkHttp-based transport compiled as a Gradle
  library project and registered by `org.lynxsdk.lynx.library-build`.
- **iOS** (`ios/`) — `NSURLSessionWebSocketTask` transport packaged as the
  `lynx-app-websocket` pod and registered by `cocoapods-lynx-library`.
- **HarmonyOS** (`harmony/`) — Network Kit WebSocket transport packaged as a
  source HAR and registered by the official Hvigor Autolink registry.

Each HarmonyOS module instance owns its connections; a `LynxViewClient`
closes them when the page or template runtime is destroyed.
