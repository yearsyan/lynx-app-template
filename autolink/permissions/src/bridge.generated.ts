// Generated from contracts/native-modules.json. Do not edit.
import {
  PERMISSIONS_MODULE_NAME,
  type PermissionsModule,
} from './native.generated.js';

/** Resolve this package's native module without a central runtime registry. */
export function requireNativeModule(): PermissionsModule {
  'background only';
  const nativeModule = NativeModules[PERMISSIONS_MODULE_NAME] as
    | PermissionsModule
    | null
    | undefined;
  if (nativeModule === undefined || nativeModule === null) {
    throw new Error('Permissions is not registered by the host');
  }
  return nativeModule;
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
