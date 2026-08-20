import type { InitData } from '@lynx-js/react';
import {
  completeNativeCall,
  decodeNativeEnvelope,
  requireNativeModule,
} from './bridge.generated.js';

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

export interface SafeAreaInsets {
  top: number;
  right: number;
  bottom: number;
  left: number;
}

export interface NativeEnvironment {
  schemaVersion: number;
  /** All native geometry is converted to Lynx logical px before delivery. */
  unit: 'px';
  safeAreaInsets: SafeAreaInsets;
}

declare module '@lynx-js/react' {
  interface InitData {
    nativeEnvironment?: NativeEnvironment;
  }
}

export type StatusBarStyle = 'dark-content' | 'light-content';

interface DeviceInfoResult {
  error?: unknown;
  value?: unknown;
}

function requireDeviceInfoModule() {
  'background only';
  return requireNativeModule();
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

function normalizeInset(value: unknown): number {
  return typeof value === 'number' && Number.isFinite(value)
    ? Math.max(0, value)
    : 0;
}

function decodeSafeAreaInsets(value: unknown): SafeAreaInsets {
  'background only';
  if (typeof value !== 'object' || value === null) {
    throw new Error('DeviceInfo returned invalid safe-area insets');
  }
  const insets = value as Partial<SafeAreaInsets>;
  if (
    typeof insets.top !== 'number' ||
    !Number.isFinite(insets.top) ||
    typeof insets.right !== 'number' ||
    !Number.isFinite(insets.right) ||
    typeof insets.bottom !== 'number' ||
    !Number.isFinite(insets.bottom) ||
    typeof insets.left !== 'number' ||
    !Number.isFinite(insets.left)
  ) {
    throw new Error('DeviceInfo returned invalid safe-area insets');
  }
  return {
    top: Math.max(0, insets.top),
    right: Math.max(0, insets.right),
    bottom: Math.max(0, insets.bottom),
    left: Math.max(0, insets.left),
  };
}

export function normalizeStatusBarStyle(style: StatusBarStyle): StatusBarStyle {
  'background only';
  if (style !== 'dark-content' && style !== 'light-content') {
    throw new Error(`Invalid status bar style: ${String(style)}`);
  }
  return style;
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

export const safeArea = {
  /** Reads the current native window safe area on demand. */
  getInsets(): Promise<SafeAreaInsets> {
    'background only';
    return new Promise((resolve, reject) => {
      requireDeviceInfoModule().getSafeAreaInsets((resultValue) => {
        'background only';
        try {
          const result = decodeNativeEnvelope(resultValue, 'DeviceInfo');
          if (typeof result.error === 'string' && result.error.length > 0) {
            reject(new Error(result.error));
            return;
          }
          resolve(decodeSafeAreaInsets(result.value));
        } catch (error) {
          reject(error instanceof Error ? error : new Error(String(error)));
        }
      });
    });
  },
};

/** Reads the first-frame/reactive safe-area value injected by the host adapter. */
export function readSafeAreaInsets(
  initData: InitData | null | undefined,
): SafeAreaInsets {
  const insets = initData?.nativeEnvironment?.safeAreaInsets;
  return {
    top: normalizeInset(insets?.top),
    right: normalizeInset(insets?.right),
    bottom: normalizeInset(insets?.bottom),
    left: normalizeInset(insets?.left),
  };
}

/** Controls the foreground color of the current native status bar. */
export const statusBar = {
  setStyle(style: StatusBarStyle): Promise<void> {
    'background only';
    const normalized = normalizeStatusBarStyle(style);
    return completeNativeCall((callback) =>
      requireDeviceInfoModule().setStatusBarStyle(normalized, callback),
    );
  },
};
