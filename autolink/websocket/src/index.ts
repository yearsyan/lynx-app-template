/**
 * Autolinked WebSocket transport for Lynx hosts on Android and iOS.
 *
 * The native module registers itself as `WebSocket`, so bundles
 * keep consuming it through `@lynx-app/native-bridge`. HarmonyOS hosts
 * continue to register their own module with the same name because Lynx
 * Autolink does not cover HarmonyOS yet.
 */

/** Name the native hosts register this module under. */
export const WEBSOCKET_MODULE_NAME = 'WebSocket';
