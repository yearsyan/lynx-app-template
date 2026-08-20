import {
  decodeNativeEnvelope,
  requireNativeModule,
} from '@lynx-app/native-runtime';
import { DEVICE_INFO_MODULE_NAME } from './native.generated.js';

export * from './native.generated.js';

/** Device and application facts reported by the native DeviceInfo module. */
export interface DeviceInfo {
  /** Hardware model: Build.MODEL on Android, utsname machine on iOS. */
  model: string;
  manufacturer: string;
  /** Platform OS version string (Android release, iOS version, HarmonyOS osFullName). */
  osVersion: string;
  /** Android SDK_INT / HarmonyOS API version; null on iOS. */
  osApiLevel: number | null;
  appVersion: string;
  appBuild: string;
  /** Logical density scale (Android density, iOS scale, HarmonyOS densityPixels). */
  density: number;
  /** BCP-47-ish locale tag of the device. */
  locale: string;
  isTablet: boolean;
  isFoldable: boolean;
}

interface DeviceInfoResult {
  error?: unknown;
  value?: unknown;
}

function requireDeviceInfoModule() {
  'background only';
  return requireNativeModule(DEVICE_INFO_MODULE_NAME);
}

function decodeDeviceInfo(value: unknown): DeviceInfo {
  'background only';
  if (typeof value !== 'object' || value === null) {
    throw new Error('DeviceInfo returned an invalid payload');
  }
  const info = value as Partial<DeviceInfo>;
  if (
    typeof info.model !== 'string' ||
    typeof info.manufacturer !== 'string' ||
    typeof info.osVersion !== 'string' ||
    (info.osApiLevel !== null && typeof info.osApiLevel !== 'number') ||
    typeof info.appVersion !== 'string' ||
    typeof info.appBuild !== 'string' ||
    typeof info.density !== 'number' ||
    !Number.isFinite(info.density) ||
    typeof info.locale !== 'string' ||
    typeof info.isTablet !== 'boolean' ||
    typeof info.isFoldable !== 'boolean'
  ) {
    throw new Error('DeviceInfo returned an invalid payload');
  }
  return info as DeviceInfo;
}

export const deviceInfo = {
  /**
   * Reads device and application facts on demand. Values that can change at
   * runtime (locale, density) are queried fresh on every call.
   */
  getInfo(): Promise<DeviceInfo> {
    'background only';
    return new Promise((resolve, reject) => {
      requireDeviceInfoModule().getInfo((resultValue) => {
        'background only';
        try {
          const result = decodeNativeEnvelope(
            resultValue,
            'DeviceInfo',
          ) as DeviceInfoResult;
          if (typeof result.error === 'string' && result.error.length > 0) {
            reject(new Error(result.error));
            return;
          }
          resolve(decodeDeviceInfo(result.value));
        } catch (error) {
          reject(error instanceof Error ? error : new Error(String(error)));
        }
      });
    });
  },
};
