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

interface DeviceInfoModule {
  getInfo(callback: (resultJSON: string) => void): void;
}

interface AppModules {
  DeviceInfo?: DeviceInfoModule;
}

interface DeviceInfoResult {
  error?: unknown;
  value?: unknown;
}

function requireDeviceInfoModule(): DeviceInfoModule {
  'background only';
  const module = (NativeModules as AppModules).DeviceInfo;
  if (module === undefined) {
    throw new Error('DeviceInfo is not registered by the host');
  }
  return module;
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
      requireDeviceInfoModule().getInfo((resultJSON) => {
        'background only';
        try {
          if (typeof resultJSON !== 'string') {
            throw new Error('DeviceInfo returned a non-string result');
          }
          const parsed = JSON.parse(resultJSON) as unknown;
          if (typeof parsed !== 'object' || parsed === null) {
            throw new Error('DeviceInfo returned an invalid result');
          }
          const result = parsed as DeviceInfoResult;
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
