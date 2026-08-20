/**
 * Registry extended by each generated Autolink raw facade through declaration
 * merging. Keeping it open removes the dependency on one global module list.
 */
// Intentionally open: each Autolink package merges its module into this
// registry through declaration merging.
// biome-ignore lint/suspicious/noEmptyInterface: declaration-merging registry
export interface NativeModuleRegistry {}

export type NativeModuleName = keyof NativeModuleRegistry & string;

/** Resolve one module after its package has augmented NativeModuleRegistry. */
export function requireNativeModule<Name extends NativeModuleName>(
  name: Name,
): NonNullable<NativeModuleRegistry[Name]> {
  'background only';
  const module = (NativeModules as NativeModuleRegistry)[name];
  if (module === undefined || module === null) {
    throw new Error(`${name} is not registered by the host`);
  }
  return module as NonNullable<NativeModuleRegistry[Name]>;
}

/** Convert the native modules' error-string callback convention to a Promise. */
export function completeNativeCall(
  action: (callback: (error: string) => void) => void,
): Promise<void> {
  'background only';
  return new Promise((resolve, reject) => {
    try {
      action((error) => {
        'background only';
        if (typeof error !== 'string') {
          reject(new Error('Native call returned an invalid error value'));
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

/**
 * Accept both modern structured bridge values and legacy JSON strings. This
 * lets each Autolink package migrate its native hosts independently.
 */
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

/** Decode and validate the common `{ value, error }` result envelope. */
export function decodeNativeEnvelope(
  value: unknown,
  source: string,
): NativeResultEnvelope {
  'background only';
  const decoded = decodeNativeValue(value, source);
  if (
    typeof decoded !== 'object' ||
    decoded === null ||
    Array.isArray(decoded)
  ) {
    throw new Error(`${source} returned an invalid result`);
  }
  return decoded as NativeResultEnvelope;
}
