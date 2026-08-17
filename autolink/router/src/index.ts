/**
 * Autolinked Lynx route navigation for hosts on Android and iOS.
 *
 * The native module registers itself as `Router`, so bundles keep
 * consuming it through `@lynx-app/native-bridge`. `open` and `close`
 * delegate to a handler the host installs, while `openURL` hands a URL
 * to the operating system, which launches whatever app — including this
 * one — registered the scheme (for example `weixin://` or the host's own
 * `lynxapp://` pages). HarmonyOS hosts register their host-owned
 * implementation manually because Lynx Autolink does not cover HarmonyOS.
 */

/** Name the native hosts register this module under. */
export const ROUTER_MODULE_NAME = 'Router';
