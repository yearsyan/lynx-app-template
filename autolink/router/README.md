# @lynx-template/autolink-router

Autolinked Lynx native library that registers `Router` on Android and iOS
hosts. Bundles keep consuming the JS API through
`@lynx-app/native-bridge`.

- **Android** (`android/`) — `open`/`close` delegate to a host-installed
  `LynxRouteHandler` (in-app `LynxPageActivity` navigation), while
  `openURL` fires an `ACTION_VIEW` intent so the system resolves any
  registered scheme, including the host's own.
- **iOS** (`ios/`) — `open`/`close` delegate to a host-installed
  `LynxRouteHandler` (`LynxPageViewController` push/present), while
  `openURL` calls `UIApplication.open(_:options:completionHandler:)`.

HarmonyOS hosts are **not** covered by Lynx Autolink and manually register
their `Navigation`-backed `Router` (with the same `openURL` contract) from
`app/harmonyApp`.
