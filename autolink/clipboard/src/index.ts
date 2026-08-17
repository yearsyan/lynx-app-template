/**
 * Autolinked system clipboard access for Lynx hosts on Android and iOS.
 *
 * The native module registers itself as `NativeClipboardModule`, so bundles
 * keep consuming it through `@lynx-template/native-bridge`. HarmonyOS hosts
 * have no clipboard module yet; Lynx Autolink would not cover them anyway.
 */

/** Name the native hosts register this module under. */
export const NATIVE_CLIPBOARD_MODULE_NAME = 'NativeClipboardModule';
