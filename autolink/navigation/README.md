# @lynx-template/autolink-navigation

Autolinked route navigation and Back interception for Lynx hosts
(Android, iOS & HarmonyOS). Exports one Lynx NativeModule, `Navigation`:

| Method | JS facade |
| --- | --- |
| `open(options, callback)` | `router.open(options): Promise<void>` |
| `close(callback)` | `router.close(): Promise<void>` |
| `openForResult(options, callback)` | `router.openForResult(options): Promise<T \| undefined>` |
| `closeWithResult(result, callback)` | `router.closeWithResult(result): Promise<void>` |
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

## Result routing

`router.openForResult(options)` takes the same options as `open` but its
Promise stays pending until the opened route closes. If that page called
`router.closeWithResult(result)`, it resolves with the result object; a plain
`close()`, a native Back gesture or any other close path resolves `undefined`.
A failed open (validation, no host) rejects immediately.

The result travels through a host-owned pending registry correlated by a
result token attached to the opened route, and is delivered from the route's
actual teardown (activity destroy / stack removal / `aboutToDisappear`), so
every close path — including predictive Back and the present dismiss
choreography — resolves exactly once. Calling `closeWithResult` on a route
that was not opened for a result closes normally and drops the result. Hosts
opt in by implementing the optional `openForResult`/`closeWithResult` members
of their route handler (default methods on Android, `@optional` on iOS,
optional interface members on HarmonyOS); the template's handlers show the
wiring.

For `animation: 'present'`, `present.enter` and `present.exit` independently
configure the new page's `opacity` and full-viewport `push` choreography. Both
phases default to `{ opacity: false, push: true }`, so the entering page starts
with zero visible area and does not fade. The deprecated `contentTransition`
flag remains a fallback for both phases' `push` value; an explicit phase value
wins.

Interactive dismissal is opt-in and platform-specific:
`present.iosSwipeDown` lets an iOS leading-edge swipe drive the configured
exit choreography, while `present.androidPredictiveBackDown` maps Android's
predictive Back progress to the same choreography. They default to `false`,
can be enabled independently, and a cancelled gesture restores the fully
presented state. With the default exit phase, the foreground page moves down
while the backdrop expands back to fullscreen.

## Back interception

`back`/`backStack` expose the lifecycle-bound Back dispatcher with an
optional native animation target:

- `back.addListener(listener)` subscribes to validated `back` global events.
- `backStack.addInterceptor(listener, { animationTargetId? })` pushes a LIFO
  interceptor; native interception stays enabled until the last entry is
  removed.
- `useBackInterceptor(onEvent, enabled?)` (from `@lynx-template/autolink-navigation/react`)
  wraps the stack in a React hook.
- `useBackDismissal(onDismiss, enabled?)` (from `@lynx-template/autolink-navigation/react`)
  turns one Back commit into a dismissal while enabled — for dialogs,
  drawers and other single-dismiss JS surfaces where Back should close the
  surface instead of the route; a cancelled gesture keeps it open.
- `<PredictiveBackOverlay>` binds Android/iOS predictive Back gestures to a
  native animation target registered as the `predictive-back-overlay` element.

On HarmonyOS the host forwards its synchronous `onBackPress` into
`NativeBackController.handleBack()` (exported by this package's HarmonyOS
HAR); enabled sessions emit a discrete start/commit pair because HarmonyOS
exposes no progress callback.

Route params typed access (`useRouteParams`) and the `InitData.route`
augmentation also live in this package's `./react` entrypoint.
