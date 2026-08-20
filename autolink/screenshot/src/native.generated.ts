// Generated from contracts/native-modules.json. Do not edit.
import '@lynx-app/native-runtime';
import type { Screenshot as RawScreenshotModule } from '../types/platform-native-module.js';

export type ScreenshotModule = RawScreenshotModule;

declare module '@lynx-app/native-runtime' {
  interface NativeModuleRegistry {
    Screenshot?: RawScreenshotModule;
  }
}

/** Name the native hosts register this module under. */
export const SCREENSHOT_MODULE_NAME = 'Screenshot' as const;
