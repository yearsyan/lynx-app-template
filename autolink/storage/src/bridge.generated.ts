// Generated from contracts/native-modules.json. Do not edit.
import { STORAGE_MODULE_NAME, type StorageModule } from './native.generated.js';

/** Resolve this package's native module without a central runtime registry. */
export function requireNativeModule(): StorageModule {
  'background only';
  const nativeModule = NativeModules[STORAGE_MODULE_NAME] as
    | StorageModule
    | null
    | undefined;
  if (nativeModule === undefined || nativeModule === null) {
    throw new Error('Storage is not registered by the host');
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
          reject(new Error('Storage returned an invalid error value'));
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
