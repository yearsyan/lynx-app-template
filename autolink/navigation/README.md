# @lynx-template/autolink-navigation

Autolinked route navigation and Back interception for Lynx hosts
(Android, iOS & HarmonyOS). Exports one Lynx NativeModule, `Navigation`:

| Method | JS facade |
| --- | --- |
| `open(options, callback)` | `router.open(options): Promise<void>` |
| `close(callback)` | `router.close(): Promise<void>` |
| `openURL(url, callback)` | `router.openURL(url): Promise<void>` |
| `setEnabled(enabled, callback)` | `back.setEnabled(enabled): Promise<void>` |
| `configure(enabled, interceptorId, targetId, revision, callback)` | `backStack` reconciliation (internal) |

## Route navigation

`open`/`close` delegate to a host-installed navigation policy because only
the host knows how to present Lynx pages:

- Android: implement `LynxRouteHandler` and install it with
  `NavigationModule.setRouteHandler(handler)` (see the template's
  `AppRouteHandler.kt`).
- iOS: implement the `LynxRouteHandler` protocol and install it with
  `NavigationModule.setRouteHandler(_:)` (see `AppRouteHandler.swift`).
- HarmonyOS: install a `NativeRouterHandler` into
  `LynxContext.contextData[ROUTE_HANDLER_CONTEXT_DATA_KEY]` (see
  `host/NativeRouterHost.ets`).

`openURL` resolves any system URL (deep links, `https://`, third-party
schemes) through the platform router and needs no host wiring.

## Back interception

`back`/`backStack` expose the lifecycle-bound Back dispatcher with an
optional native animation target:

- `back.addListener(listener)` subscribes to validated `back` global events.
- `backStack.addInterceptor(listener, { animationTargetId? })` pushes a LIFO
  interceptor; native interception stays enabled until the last entry is
  removed.
- `useBackInterceptor(onEvent, enabled?)` (from `@lynx-template/autolink-navigation/react`)
  wraps the stack in a React hook.
- `<PredictiveBackOverlay>` binds Android/iOS predictive Back gestures to a
  native animation target registered as the `predictive-back-overlay` element.

On HarmonyOS the host forwards its synchronous `onBackPress` into
`NativeBackController.handleBack()` (exported by this package's HarmonyOS
HAR); enabled sessions emit a discrete start/commit pair because HarmonyOS
exposes no progress callback.

Route params typed access (`useRouteParams`) and the `InitData.route`
augmentation also live in this package's `./react` entrypoint.
