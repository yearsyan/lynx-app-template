// Generated from contracts/native-modules.json. Do not edit.
import {
  SECURE_STORAGE_MODULE_NAME,
  type SecureStorageModule,
} from './native.generated.js';

/** Resolve this package's native module without a central runtime registry. */
export function requireNativeModule(): SecureStorageModule {
  'background only';
  const nativeModule = NativeModules[SECURE_STORAGE_MODULE_NAME] as
    | SecureStorageModule
    | null
    | undefined;
  if (nativeModule === undefined || nativeModule === null) {
    throw new Error('SecureStorage is not registered by the host');
  }
  return nativeModule;
}
