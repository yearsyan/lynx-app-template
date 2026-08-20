// Generated from contracts/native-modules.json. Do not edit.
import {
  WEBSOCKET_MODULE_NAME,
  type WebSocketModule,
} from './native.generated.js';

/** Resolve this package's native module without a central runtime registry. */
export function requireNativeModule(): WebSocketModule {
  'background only';
  const nativeModule = NativeModules[WEBSOCKET_MODULE_NAME] as
    | WebSocketModule
    | null
    | undefined;
  if (nativeModule === undefined || nativeModule === null) {
    throw new Error('WebSocket is not registered by the host');
  }
  return nativeModule;
}
