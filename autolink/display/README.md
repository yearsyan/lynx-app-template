# @lynx-template/autolink-display

Autolinked Lynx native library that registers `Display` on Android, iOS and
HarmonyOS hosts. Bundles consume it through `@lynx-app/native-bridge#display`.

All widths are **Lynx logical pixels** (Android dp, iOS points, HarmonyOS vp)
— the same unit Lynx layout consumes — and are read on demand so rotation,
fold/unfold and multi-window changes are reflected immediately.

| Method | Android | iOS | HarmonyOS |
| --- | --- | --- | --- |
| `screenWidth` | `LynxContext.getScreenMetrics()` (full screen) | `UIScreen.mainScreen.bounds` | default `Display` width / density |
| `windowWidth` | `WindowMetrics` of the host Activity (API 30+, display size below); falls back to screen width when no Activity is reachable | key window of the foreground-active scene, preferring the LynxView's own window; falls back to screen width | `LynxContext.getCurrentWindow()` |
| `lynxViewWidth` | `LynxContext.getLynxView().getWidth()` | `[LynxContext getLynxView].bounds` | `LynxContext.getRectangleById('')`, converted from px to vp |

Each method answers a JSON envelope `{ "value": <number> }` or
`{ "error": <string> }`. `lynxViewWidth` rejects when no LynxView is
attached and reports `0` while the view has not been laid out yet.

The HarmonyOS source HAR is registered by the official Hvigor Autolink
registry. Window brightness and keep-screen-on use the current Lynx window;
no page-scoped registration object is required.
