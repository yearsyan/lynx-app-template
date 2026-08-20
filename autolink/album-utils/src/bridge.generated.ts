// Generated from contracts/native-modules.json. Do not edit.
import {
  ALBUM_UTILS_MODULE_NAME,
  type AlbumUtilsModule,
} from './native.generated.js';

/** Resolve this package's native module without a central runtime registry. */
export function requireNativeModule(): AlbumUtilsModule {
  'background only';
  const nativeModule = NativeModules[ALBUM_UTILS_MODULE_NAME] as
    | AlbumUtilsModule
    | null
    | undefined;
  if (nativeModule === undefined || nativeModule === null) {
    throw new Error('AlbumUtils is not registered by the host');
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
          reject(new Error('AlbumUtils returned an invalid error value'));
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

/** Accept structured bridge values and legacy JSON strings during migration. */
export function decodeNativeValue(value: unknown, source: string): unknown {
  'background only';
  if (typeof value !== 'string') {
    return value;
  }
  try {
    return JSON.parse(value) as unknown;
  } catch {
    throw new Error(`${source} returned invalid JSON`);
  }
}
