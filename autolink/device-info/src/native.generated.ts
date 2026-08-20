// Generated from contracts/native-modules.json. Do not edit.
import '@lynx-app/native-runtime';
import type { DeviceInfo as RawDeviceInfoModule } from '../types/platform-native-module.js';

export type DeviceInfoModule = RawDeviceInfoModule;

declare module '@lynx-app/native-runtime' {
  interface NativeModuleRegistry {
    DeviceInfo?: RawDeviceInfoModule;
  }
}

/** Name the native hosts register this module under. */
export const DEVICE_INFO_MODULE_NAME = 'DeviceInfo' as const;
