# @lynx-template/autolink-toast

Autolinked Lynx native library that registers `Toast` on Android, iOS and
HarmonyOS hosts. Bundles import `toast` from this package root.

`show(message, options)` renders the bubble **inside the app's own window**
on every platform — never through the system toast/notification pipeline —
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
- **HarmonyOS** — the same bubble is built as a `ComponentContent` and added
  to the window's `OverlayManager`, fading in/out; the overlay is
  click-through, a new toast replaces the current one, and `durationMs` is
  honored exactly. (`promptAction.showToast` is deliberately not used: its
  theme blur material overrides custom background colors, it renders no
  icons, and it clamps durations to 1500–10000ms.)

The HarmonyOS `ToastModule` ships as the `harmony/` source HAR and resolves
the current window from `LynxContext`, so the official global HarmonyOS
Autolink provider needs no host parameter.
