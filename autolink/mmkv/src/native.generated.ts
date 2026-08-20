// Generated from contracts/native-modules.json. Do not edit.
import '@lynx-app/native-runtime';
import type { KV as RawKVModule } from '../types/platform-native-module.js';

export type KVModule = RawKVModule;

declare module '@lynx-app/native-runtime' {
  interface NativeModuleRegistry {
    KV?: RawKVModule;
  }
}

/** Name the native hosts register this module under. */
export const KV_MODULE_NAME = 'KV' as const;
