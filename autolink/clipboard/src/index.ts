/**
 * Autolinked system clipboard access for Lynx hosts on Android and iOS.
 *
 * The native module registers itself as `Clipboard`, so bundles
 * keep consuming it through `@lynx-app/native-bridge`. HarmonyOS hosts
 * register their host-owned implementation manually because Lynx Autolink
 * does not cover HarmonyOS.
 */

/** Name the native hosts register this module under. */
export const CLIPBOARD_MODULE_NAME = 'Clipboard';
