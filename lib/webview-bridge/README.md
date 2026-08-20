# @lynx-app/webview-bridge

Browser-side typed client for pages loaded inside the autolinked
`<module-webview>` element. The host injects `window.__lynxNativeBridge` into
every bridged document; this package wraps that raw protocol with typed
facades (`kv`, `clipboard`, `haptics`, `statusBar`, `getDeviceInfo`) and an
`invokeNative` escape hatch whose module/method names are checked against the
generated contracts in `@lynx-app/native-contracts`.

```ts
import { haptics, isNativeBridgeAvailable, kv } from '@lynx-app/webview-bridge';

if (isNativeBridgeAvailable()) {
  await kv.setString('counter', '1');
  await haptics.impact('light');
}
```

## Who consumes this package

Web apps shipped to the `<module-webview>` element — either a workspace
package in this repository or an external web project that vendors these
files. Lynx bundles (`bundle/*`) intentionally do **not** depend on it: they
talk to native modules through each selected Autolink package facade instead.

The self-contained demo page in `bundle/main/src/pages/api-media.tsx` inlines
the raw `window.__lynxNativeBridge` protocol on purpose — HTML embedded as a
string cannot import npm packages, while a real web app can and should use
this client.

On hosts without the bridge (stock WebView, plain browsers),
`isNativeBridgeAvailable()` returns `false` and every facade rejects with
`NativeBridgeUnavailableError`.

See [docs/webview-module-bridge.md](../../docs/webview-module-bridge.md) for
the protocol, capability-list authorization, and the three host adapters.
