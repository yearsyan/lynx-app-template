import { completeNativeCall, requireNativeModule } from './bridge.generated.js';

export * from './native.generated.js';

function requireStorageModule() {
  'background only';
  return requireNativeModule();
}

function validateKey(key: string): void {
  'background only';
  if (key.trim().length === 0) {
    throw new Error('Storage key must not be empty');
  }
}

// ---------------------------------------------------------------------------
// Shared MMKV-backed KV store
// ---------------------------------------------------------------------------

/**
 * Promise-based, validated access to the shared MMKV-backed KV store.
 * String primitives for every bundle; JSON encoding stays in TypeScript.
 */
export const kv = {
  setString(key: string, value: string): Promise<void> {
    'background only';
    validateKey(key);
    return completeNativeCall((callback) =>
      requireStorageModule().setString(key, value, callback),
    );
  },

  getString(
    key: string,
    defaultValue: string | null = null,
  ): Promise<string | null> {
    'background only';
    validateKey(key);
    return new Promise((resolve) => {
      const module = requireStorageModule();
      if (defaultValue === null) {
        module.getStringOrNull(key, (value) => {
          'background only';
          resolve(typeof value === 'string' ? value : null);
        });
        return;
      }
      module.getString(key, defaultValue, (value) => {
        'background only';
        resolve(typeof value === 'string' ? value : defaultValue);
      });
    });
  },

  remove(key: string): Promise<void> {
    'background only';
    validateKey(key);
    return completeNativeCall((callback) =>
      requireStorageModule().remove(key, callback),
    );
  },

  clear(): Promise<void> {
    'background only';
    return completeNativeCall((callback) =>
      requireStorageModule().clear(callback),
    );
  },

  contains(key: string): Promise<boolean> {
    'background only';
    validateKey(key);
    return new Promise((resolve) => {
      requireStorageModule().contains(key, resolve);
    });
  },

  async setJSON(key: string, value: unknown): Promise<void> {
    'background only';
    await this.setString(key, JSON.stringify(value));
  },

  async getJSON<T>(key: string, defaultValue: T): Promise<T> {
    'background only';
    const serialized = await this.getString(key);
    if (serialized === null) {
      return defaultValue;
    }
    try {
      return JSON.parse(serialized) as T;
    } catch {
      return defaultValue;
    }
  },
};

// ---------------------------------------------------------------------------
// Small-secret secure store
// ---------------------------------------------------------------------------

/** Mirrors the per-platform native value-size guards. */
const MAX_SECURE_VALUE_LENGTH = 64 * 1024;

/**
 * Small-secret string storage backed by Android Keystore encryption, the
 * iOS Keychain and HarmonyOS HUKS. Not a general-purpose store: values are
 * limited to short strings such as tokens and session payloads.
 */
export const secureStorage = {
  setString(key: string, value: string): Promise<void> {
    'background only';
    validateKey(key);
    if (value.length > MAX_SECURE_VALUE_LENGTH) {
      return Promise.reject(
        new Error(
          `Secure storage value is limited to ${MAX_SECURE_VALUE_LENGTH} characters`,
        ),
      );
    }
    return completeNativeCall((callback) =>
      requireStorageModule().secureSetString(key, value, callback),
    );
  },

  getString(
    key: string,
    defaultValue: string | null = null,
  ): Promise<string | null> {
    'background only';
    validateKey(key);
    return new Promise((resolve) => {
      const module = requireStorageModule();
      if (defaultValue === null) {
        module.secureGetStringOrNull(key, (value) => {
          'background only';
          resolve(typeof value === 'string' ? value : null);
        });
        return;
      }
      module.secureGetString(key, defaultValue, (value) => {
        'background only';
        resolve(typeof value === 'string' ? value : defaultValue);
      });
    });
  },

  remove(key: string): Promise<void> {
    'background only';
    validateKey(key);
    return completeNativeCall((callback) =>
      requireStorageModule().secureRemove(key, callback),
    );
  },
};
