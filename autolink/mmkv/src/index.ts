import { completeNativeCall, requireNativeModule } from './bridge.generated.js';

export * from './native.generated.js';

function requireKVModule() {
  'background only';
  return requireNativeModule();
}

function validateKey(key: string): void {
  'background only';
  if (key.trim().length === 0) {
    throw new Error('MMKV key must not be empty');
  }
}

/** Promise-based, validated access to the raw MMKV NativeModule contract. */
export const kv = {
  setString(key: string, value: string): Promise<void> {
    'background only';
    validateKey(key);
    return completeNativeCall((callback) =>
      requireKVModule().setString(key, value, callback),
    );
  },

  getString(
    key: string,
    defaultValue: string | null = null,
  ): Promise<string | null> {
    'background only';
    validateKey(key);
    return new Promise((resolve) => {
      requireKVModule().getString(key, defaultValue, resolve);
    });
  },

  remove(key: string): Promise<void> {
    'background only';
    validateKey(key);
    return completeNativeCall((callback) =>
      requireKVModule().remove(key, callback),
    );
  },

  clear(): Promise<void> {
    'background only';
    return completeNativeCall((callback) => requireKVModule().clear(callback));
  },

  contains(key: string): Promise<boolean> {
    'background only';
    validateKey(key);
    return new Promise((resolve) => {
      requireKVModule().contains(key, resolve);
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
