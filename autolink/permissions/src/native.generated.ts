// Generated from contracts/native-modules.json. Do not edit.
import '@lynx-app/native-runtime';
import type { Permissions as RawPermissionsModule } from '../types/platform-native-module.js';

export type PermissionsModule = RawPermissionsModule;

declare module '@lynx-app/native-runtime' {
  interface NativeModuleRegistry {
    Permissions?: RawPermissionsModule;
  }
}

/** Name the native hosts register this module under. */
export const PERMISSIONS_MODULE_NAME = 'Permissions' as const;
