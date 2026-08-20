# @lynx-template/autolink-router

Autolinked Lynx native library that registers `Router` on Android, iOS and
HarmonyOS hosts. The package root exports its Promise API; the optional
`@lynx-template/autolink-router/react` entry exports `useRouteParams`.

- **Android** (`android/`) — `open`/`close` delegate to a host-installed
  `LynxRouteHandler` (in-app `LynxPageActivity` navigation), while
  `openURL` fires an `ACTION_VIEW` intent so the system resolves any
  registered scheme, including the host's own.
- **iOS** (`ios/`) — `open`/`close` delegate to a host-installed
  `LynxRouteHandler` (`LynxPageViewController` push/present), while
  `openURL` calls `UIApplication.open(_:options:completionHandler:)`.
- **HarmonyOS** (`harmony/`) — the official Hvigor Autolink registry installs
  `RouterModule`; `open`/`close` delegate through `LynxContext.contextData` to
  the app's `Navigation` policy, while `openURL` uses `UIAbility.openLink`.

Only the app-specific navigation handler remains in the HarmonyOS host. The
NativeModule class and its registration are owned by the Autolink package.
