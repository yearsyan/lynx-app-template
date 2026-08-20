// Generated from contracts/native-modules.json. Do not edit.
import {
  BACK_MODULE_NAME,
  type BackModule,
  STATUS_BAR_MODULE_NAME,
  type StatusBarModule,
} from './native.js';

/** Resolve the host-owned Back module for the current LynxView. */
export function requireBackModule(): BackModule {
  'background only';
  const nativeModule = NativeModules[BACK_MODULE_NAME] as
    | BackModule
    | null
    | undefined;
  if (nativeModule === undefined || nativeModule === null) {
    throw new Error('Back is not registered by the host');
  }
  return nativeModule;
}

/** Resolve the host-owned StatusBar module for the current LynxView. */
export function requireStatusBarModule(): StatusBarModule {
  'background only';
  const nativeModule = NativeModules[STATUS_BAR_MODULE_NAME] as
    | StatusBarModule
    | null
    | undefined;
  if (nativeModule === undefined || nativeModule === null) {
    throw new Error('StatusBar is not registered by the host');
  }
  return nativeModule;
}

/** Convert the host modules' error-string callback convention to a Promise. */
export function completeNativeCall(
  action: (callback: (error: string) => void) => void,
): Promise<void> {
  'background only';
  return new Promise((resolve, reject) => {
    try {
      action((error) => {
        'background only';
        if (typeof error !== 'string') {
          reject(new Error('Native host call returned an invalid error value'));
          return;
        }
        if (error.length > 0) {
          reject(new Error(error));
        } else {
          resolve();
        }
      });
    } catch (error) {
      reject(error instanceof Error ? error : new Error(String(error)));
    }
  });
}
