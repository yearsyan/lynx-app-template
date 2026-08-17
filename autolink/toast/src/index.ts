/**
 * Autolinked toast notifications for Lynx hosts on Android and iOS.
 *
 * The native module registers itself as `Toast`, so bundles
 * keep consuming it through `@lynx-app/native-bridge`. HarmonyOS hosts
 * register their host-owned implementation manually because Lynx Autolink
 * does not cover HarmonyOS.
 */

/** Name the native hosts register this module under. */
export const TOAST_MODULE_NAME = 'Toast';
