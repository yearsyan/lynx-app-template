// Generated from contracts/native-modules.json. Do not edit.
import {
  BIOMETRIC_MODULE_NAME,
  type BiometricModule,
} from './native.generated.js';

/** Resolve this package's native module without a central runtime registry. */
export function requireNativeModule(): BiometricModule {
  'background only';
  const nativeModule = NativeModules[BIOMETRIC_MODULE_NAME] as
    | BiometricModule
    | null
    | undefined;
  if (nativeModule === undefined || nativeModule === null) {
    throw new Error('Biometric is not registered by the host');
  }
  return nativeModule;
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

/** Decode a legacy JSON value, then validate its result envelope. */
export function decodeNativeEnvelope(
  value: unknown,
  source: string,
): NativeResultEnvelope {
  'background only';
  return validateNativeEnvelope(decodeNativeValue(value, source), source);
}
