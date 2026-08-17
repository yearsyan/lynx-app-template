# @lynx-template/autolink-display

Autolinked Lynx native library that registers `Display` on Android and iOS
hosts. Bundles consume it through `@lynx-app/native-bridge#display`.

All widths are **Lynx logical pixels** (Android dp, iOS points) — the same
unit Lynx layout consumes — and are read on demand so rotation, fold/unfold
and multi-window changes are reflected immediately.

| Method | Android | iOS |
| --- | --- | --- |
| `screenWidth` | `LynxContext.getScreenMetrics()` (full screen) | `UIScreen.mainScreen.bounds` |
| `windowWidth` | `WindowMetrics` of the host Activity (API 30+, display size below); falls back to screen width when no Activity is reachable | key window of the foreground-active scene, preferring the LynxView's own window; falls back to screen width |
| `lynxViewWidth` | `LynxContext.getLynxView().getWidth()` | `[LynxContext getLynxView].bounds` |

Each method answers a JSON envelope `{ "value": <number> }` or
`{ "error": <string> }`. `lynxViewWidth` rejects when no LynxView is
attached and reports `0` while the view has not been laid out yet.

HarmonyOS hosts are **not** covered by Lynx Autolink and manually register
their `DisplayModule` from `app/harmonyApp`; the LynxView width there is
measured by the host via `onAreaChange` because the HarmonyOS LynxContext
does not expose its view.
