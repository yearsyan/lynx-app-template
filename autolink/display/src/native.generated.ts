// Generated from contracts/native-modules.json. Do not edit.
import '@lynx-app/native-runtime';
import type { Display as RawDisplayModule } from '../types/platform-native-module.js';

export type DisplayModule = RawDisplayModule;

declare module '@lynx-app/native-runtime' {
  interface NativeModuleRegistry {
    Display?: RawDisplayModule;
  }
}

/** Name the native hosts register this module under. */
export const DISPLAY_MODULE_NAME = 'Display' as const;
