/**
 * Autolinked MMKV-backed key/value storage for Lynx hosts on Android and iOS.
 *
 * The native module registers itself as `NativeKVModule`, so bundles keep
 * consuming it through `@lynx-template/native-bridge`. HarmonyOS hosts
 * continue to register their own module with the same name because Lynx
 * Autolink does not cover HarmonyOS yet.
 */

/** Name the native hosts register this module under. */
export const NATIVE_KV_MODULE_NAME = 'NativeKVModule';
