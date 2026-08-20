// Generated from contracts/native-modules.json. Do not edit.
import '@lynx-app/native-runtime';
import type { Toast as RawToastModule } from '../types/platform-native-module.js';

export type ToastModule = RawToastModule;

declare module '@lynx-app/native-runtime' {
  interface NativeModuleRegistry {
    Toast?: RawToastModule;
  }
}

/** Name the native hosts register this module under. */
export const TOAST_MODULE_NAME = 'Toast' as const;
