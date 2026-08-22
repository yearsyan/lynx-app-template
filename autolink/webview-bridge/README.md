# Autolink WebView bridge

This package owns the complete `<module-webview>` feature: the Android and iOS
Autolink element, its Lynx element typings, and the browser-side typed client.
The element exposes only the native modules named in
`params['module-bridge'].modules`.

The native library intentionally does not own an app module list. Each host
attaches the module registry already used by its LynxView through a small
explicit host adapter. HarmonyOS keeps an explicit behavior adapter: it layers
the page's module map over the global Autolink registry (enumerated through
the generated `@lynx/lynx_autolink_registry` package's `collectGlobalModules()`),
because the global provider does not expose a page's host-scoped module map.

## Browser client

Pages loaded inside `<module-webview>` can use the `/client` export to wrap the
injected `window.__lynxNativeBridge` protocol with typed facades (`kv`,
`clipboard`, `haptics`, `statusBar`, `getDeviceInfo`, `getSafeAreaInsets`) and a generic
`invokeNative` escape hatch. Its module and method names come from the
package-local generated contract.

```ts
import {
  haptics,
  isNativeBridgeAvailable,
  kv,
} from '@lynx-template/autolink-webview-bridge/client';

if (isNativeBridgeAvailable()) {
  await kv.setString('counter', '1');
  await haptics.impact('light');
}
```

Lynx bundles intentionally use each NativeModule package facade instead. The
self-contained demo in `bundle/main/src/pages/api-media.tsx` inlines the raw
protocol because HTML embedded as a string cannot import a workspace package.

On stock WebView hosts and plain browsers,
`isNativeBridgeAvailable()` returns false and every facade rejects with
`NativeBridgeUnavailableError`.

See `docs/webview-module-bridge.md` for the protocol, capability authorization,
and three-host adapters.
