// Generated from contracts/native-modules.json. Do not edit.
import '@lynx-app/native-runtime';
import type { SecureStorage as RawSecureStorageModule } from '../types/platform-native-module.js';

export type SecureStorageModule = RawSecureStorageModule;

declare module '@lynx-app/native-runtime' {
  interface NativeModuleRegistry {
    SecureStorage?: RawSecureStorageModule;
  }
}

/** Name the native hosts register this module under. */
export const SECURE_STORAGE_MODULE_NAME = 'SecureStorage' as const;
