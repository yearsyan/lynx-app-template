/**
 * Small-secret string storage backed by Android Keystore encryption, the
 * iOS Keychain and HarmonyOS HUKS. Not a general-purpose store: values are
 * limited to short strings such as tokens and session payloads.
 */
import { NATIVE_MODULE_NAMES } from '@lynx-app/native-contracts';
import { requireNativeModule } from './moduleRegistry.js';

/** Mirrors the per-platform native value-size guards. */
const MAX_VALUE_LENGTH = 64 * 1024;

function requireSecureStorageModule() {
  'background only';
  return requireNativeModule(NATIVE_MODULE_NAMES.SecureStorage);
}

function validateKey(key: string): void {
  'background only';
  if (key.trim().length === 0) {
    throw new Error('Secure storage key must not be empty');
  }
}

export const secureStorage = {
  setString(key: string, value: string): Promise<void> {
    'background only';
    validateKey(key);
    if (value.length > MAX_VALUE_LENGTH) {
      return Promise.reject(
        new Error(
          `Secure storage value is limited to ${MAX_VALUE_LENGTH} characters`,
        ),
      );
    }
    return new Promise((resolve, reject) => {
      requireSecureStorageModule().setString(key, value, (error) => {
        'background only';
        if (error.length > 0) {
          reject(new Error(error));
        } else {
          resolve();
        }
      });
    });
  },

  getString(
    key: string,
    defaultValue: string | null = null,
  ): Promise<string | null> {
    'background only';
    validateKey(key);
    return new Promise((resolve) => {
      requireSecureStorageModule().getString(key, defaultValue, resolve);
    });
  },

  remove(key: string): Promise<void> {
    'background only';
    validateKey(key);
    return new Promise((resolve, reject) => {
      requireSecureStorageModule().remove(key, (error) => {
        'background only';
        if (error.length > 0) {
          reject(new Error(error));
        } else {
          resolve();
        }
      });
    });
  },
};
