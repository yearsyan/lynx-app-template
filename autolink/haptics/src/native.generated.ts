// Generated from contracts/native-modules.json. Do not edit.
import '@lynx-app/native-runtime';
import type { Haptics as RawHapticsModule } from '../types/platform-native-module.js';

export type HapticsModule = RawHapticsModule;

declare module '@lynx-app/native-runtime' {
  interface NativeModuleRegistry {
    Haptics?: RawHapticsModule;
  }
}

/** Name the native hosts register this module under. */
export const HAPTICS_MODULE_NAME = 'Haptics' as const;
