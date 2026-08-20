// Generated from contracts/native-modules.json. Do not edit.
import '@lynx-app/native-runtime';
import type { Router as RawRouterModule } from '../types/platform-native-module.js';

export type RouterModule = RawRouterModule;

declare module '@lynx-app/native-runtime' {
  interface NativeModuleRegistry {
    Router?: RawRouterModule;
  }
}

/** Name the native hosts register this module under. */
export const ROUTER_MODULE_NAME = 'Router' as const;
