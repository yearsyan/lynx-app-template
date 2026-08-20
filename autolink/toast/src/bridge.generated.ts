// Generated from contracts/native-modules.json. Do not edit.
import { TOAST_MODULE_NAME, type ToastModule } from './native.generated.js';

/** Resolve this package's native module without a central runtime registry. */
export function requireNativeModule(): ToastModule {
  'background only';
  const nativeModule = NativeModules[TOAST_MODULE_NAME] as
    | ToastModule
    | null
    | undefined;
  if (nativeModule === undefined || nativeModule === null) {
    throw new Error('Toast is not registered by the host');
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
          reject(new Error('Toast returned an invalid error value'));
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
