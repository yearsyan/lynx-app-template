// Generated from contracts/native-modules.json. Do not edit.
import '@lynx-app/native-runtime';
import type { Biometric as RawBiometricModule } from '../types/platform-native-module.js';

export type BiometricModule = RawBiometricModule;

declare module '@lynx-app/native-runtime' {
  interface NativeModuleRegistry {
    Biometric?: RawBiometricModule;
  }
}

/** Name the native hosts register this module under. */
export const BIOMETRIC_MODULE_NAME = 'Biometric' as const;
