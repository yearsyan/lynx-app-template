// Generated from contracts/native-modules.json. Do not edit.
import {
  LOCAL_NOTIFICATION_MODULE_NAME,
  type LocalNotificationModule,
} from './native.generated.js';

/** Resolve this package's native module without a central runtime registry. */
export function requireNativeModule(): LocalNotificationModule {
  'background only';
  const nativeModule = NativeModules[LOCAL_NOTIFICATION_MODULE_NAME] as
    | LocalNotificationModule
    | null
    | undefined;
  if (nativeModule === undefined || nativeModule === null) {
    throw new Error('LocalNotification is not registered by the host');
  }
  return nativeModule;
}

/** Convert the native error-string callback convention to a Promise. */
export function completeNativeCall(
  action: (callback: (error: string) => void) => void,
): Promise<void> {
  'background only';
  return new Promise((resolve, reject) => {
    try {
      action((error) => {
        'background only';
        if (typeof error !== 'string') {
          reject(
            new Error('LocalNotification returned an invalid error value'),
          );
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

export interface NativeResultEnvelope {
  error?: unknown;
  value?: unknown;
}

/** Validate the common structured { value, error } result envelope. */
export function validateNativeEnvelope(
  value: unknown,
  source: string,
): NativeResultEnvelope {
  'background only';
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    throw new Error(`${source} returned an invalid result`);
  }
  return value as NativeResultEnvelope;
}
