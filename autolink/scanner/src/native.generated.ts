// Generated from contracts/native-modules.json. Do not edit.
import '@lynx-app/native-runtime';
import type { Scanner as RawScannerModule } from '../types/platform-native-module.js';

export type ScannerModule = RawScannerModule;

declare module '@lynx-app/native-runtime' {
  interface NativeModuleRegistry {
    Scanner?: RawScannerModule;
  }
}

/** Name the native hosts register this module under. */
export const SCANNER_MODULE_NAME = 'Scanner' as const;
