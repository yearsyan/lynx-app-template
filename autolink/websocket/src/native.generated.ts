// Generated from contracts/native-modules.json. Do not edit.
import '@lynx-app/native-runtime';
import type { WebSocket as RawWebSocketModule } from '../types/platform-native-module.js';

export type WebSocketModule = RawWebSocketModule;

declare module '@lynx-app/native-runtime' {
  interface NativeModuleRegistry {
    WebSocket?: RawWebSocketModule;
  }
}

/** Name the native hosts register this module under. */
export const WEBSOCKET_MODULE_NAME = 'WebSocket' as const;
