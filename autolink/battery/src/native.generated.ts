// Generated from contracts/native-modules.json. Do not edit.
import '@lynx-app/native-runtime';
import type { Battery as RawBatteryModule } from '../types/platform-native-module.js';

export type BatteryModule = RawBatteryModule;

declare module '@lynx-app/native-runtime' {
  interface NativeModuleRegistry {
    Battery?: RawBatteryModule;
  }
}

/** Name the native hosts register this module under. */
export const BATTERY_MODULE_NAME = 'Battery' as const;
