/**
 * Autolinked system file picker and URI-aware file operations for Lynx hosts
 * on Android and iOS.
 *
 * The native module registers itself as `FileSystem`, so bundles
 * keep consuming it through `@lynx-app/native-bridge`. HarmonyOS hosts
 * register their host-owned implementation manually because Lynx Autolink
 * does not cover HarmonyOS.
 */

/** Name the native hosts register this module under. */
export const FILE_SYSTEM_MODULE_NAME = 'FileSystem';
