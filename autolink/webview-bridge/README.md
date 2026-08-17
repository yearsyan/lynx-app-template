# Autolink WebView bridge

This native library registers the `<module-webview>` element on Android and
iOS. The element exposes only the native modules named in
`params['module-bridge'].modules`.

The library intentionally does not own an app module list. Each host attaches
the module registry already used by its LynxView through a small explicit host
adapter. HarmonyOS keeps an explicit behavior adapter because Lynx 4.0 does not
release HarmonyOS Autolink support.
