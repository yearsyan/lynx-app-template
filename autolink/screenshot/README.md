# @lynx-template/autolink-screenshot

Autolinked Lynx native library that registers `Screenshot` on Android, iOS
and HarmonyOS hosts. Bundles consume it through
`@lynx-app/native-bridge#screenshot`.

Both entry points encode into `<cache>/LynxImages/<uuid>-<name>.<ext>` and
answer a JSON envelope `{ "value": { "uri", "width", "height" } }` or
`{ "error": <string> }`:

| Method | Android | iOS | HarmonyOS |
| --- | --- | --- | --- |
| `capture` | resolves the `LynxView` from `LynxContext` (or the element matching `idSelector` via `LynxView.findViewByIdSelector`) and draws it into a bitmap | resolves the `LynxView` from `LynxContext` (or the element matching `idSelector` via `viewWithIdSelector:`) and renders it with `drawViewHierarchyInRect`, falling back to `layer.renderInContext` | `LynxContext.getComponentSnapshot(idSelector)`; an empty selector captures the Lynx root |
| `capturePage` | `PixelCopy` of the Activity window (API 24/25 fall back to drawing the decor view) — the composited result including native chrome, no screenshot permission | key-window snapshot of the foreground-active scene | `LynxContext.getCurrentWindow().snapshot()` |

Notes:

- JPEG targets pre-composite against white because JPEG has no alpha channel.
- View drawing happens on the main thread; encoding and file IO run off it.
- `capture` rejects when the LynxView is not attached, the `idSelector`
  matches nothing, or the target has not been laid out (`width`/`height` 0).

The HarmonyOS source HAR is registered by the official Hvigor Autolink
registry. It uses the Lynx 4.2 component snapshot APIs directly, so it needs
no host container IDs or page-scoped registration object.
