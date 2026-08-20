// Generated from contracts/native-modules.json. Do not edit.
import '@lynx-app/native-runtime';
import type { Sensors as RawSensorsModule } from '../types/platform-native-module.js';

export type SensorsModule = RawSensorsModule;

declare module '@lynx-app/native-runtime' {
  interface NativeModuleRegistry {
    Sensors?: RawSensorsModule;
  }
}

/** Name the native hosts register this module under. */
export const SENSORS_MODULE_NAME = 'Sensors' as const;
