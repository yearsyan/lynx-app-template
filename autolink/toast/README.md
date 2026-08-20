# @lynx-template/autolink-toast

Autolinked Lynx native library that registers `Toast` on Android and iOS
hosts. Bundles import `toast` from this package root.

`show(message, options)` renders the bubble **inside the app's own window**
on both platforms — never through the system toast/notification pipeline —
so:

- styling is fully custom and identical under any system theme;
- no notification permission is needed. (System toasts on Android are
  routed through `NotificationManagerService` and are silently dropped when
  notifications are blocked or `POST_NOTIFICATIONS` is denied.)

Options:

| Key | Default | Notes |
| --- | --- | --- |
| `type` | `'info'` | `'info'` / `'success'` / `'error'`; picks the icon glyph and tint |
| `showIcon` | `true` | Icon is a colored circle glyph (`i` / `✓` / `✕`) |
| `backgroundColor` | `#E62E2A33` | `#RRGGBB` or `#AARRGGBB` |
| `textColor` | white | `#RRGGBB` or `#AARRGGBB` |
| `durationMs` | `2000` | Honored exactly on both platforms |

- **Android** — a bubble view is added to the host Activity's decor view
  (bottom-center, above the LynxView), fading in/out; a new toast replaces
  the current one.
- **iOS** — the same bubble is drawn at the bottom of the LynxView's window
  (falling back to the key window).

HarmonyOS ships the `promptAction.showToast`-backed `ToastModule` as the
`harmony/` source HAR. It resolves the current window from `LynxContext`, so
the official global HarmonyOS Autolink provider needs no host parameter.
The ArkUI toast is also in-window and permission-free; it honors
`backgroundColor`/`textColor` natively, renders the icon as a text prefix,
and clamps `durationMs` to the system range (1500–10000ms).
