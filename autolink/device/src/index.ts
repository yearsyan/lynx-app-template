import type { InitData } from '@lynx-js/react';
import {
  completeNativeCall,
  decodeNativeEnvelope,
  requireNativeModule,
  validateNativeEnvelope,
} from './bridge.generated.js';

export * from './native.generated.js';

function requireDeviceModule() {
  'background only';
  return requireNativeModule();
}

// ---------------------------------------------------------------------------
// Device facts, safe area and status bar
// ---------------------------------------------------------------------------

/** Device and application facts reported by the native Device module. */
export interface DeviceInfo {
  /** Hardware model: Build.MODEL on Android, utsname machine on iOS. */
  model: string;
  manufacturer: string;
  /** Platform OS version string (Android release, iOS version, HarmonyOS osFullName). */
  osVersion: string;
  /** Android SDK_INT / HarmonyOS API version; null on iOS. */
  osApiLevel: number | null;
  /** Application id: Android packageName / iOS bundle identifier / HarmonyOS bundleName. */
  bundleId: string;
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

export type ColorScheme = 'light' | 'dark';

export type AppLocale = 'zh-Hans' | 'en';

export interface NativeEnvironment {
  schemaVersion: number;
  /** All native geometry is converted to Lynx logical px before delivery. */
  unit: 'px';
  /** Android status-bar inset without display-cutout expansion. */
  statusBarInsetTop?: number;
  /** Android bottom navigation-bar inset, retained while the IME is visible. */
  navigationBarInsetBottom?: number;
  /** Resolved system appearance for this app instance. */
  colorScheme?: ColorScheme;
  /** Resolved app locale as a BCP-47 language tag. */
  locale?: string;
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

function decodeDeviceInfo(value: unknown): DeviceInfo {
  'background only';
  if (typeof value !== 'object' || value === null) {
    throw new Error('Device returned an invalid payload');
  }
  const info = value as Partial<DeviceInfo>;
  if (
    typeof info.model !== 'string' ||
    typeof info.manufacturer !== 'string' ||
    typeof info.osVersion !== 'string' ||
    (info.osApiLevel !== null && typeof info.osApiLevel !== 'number') ||
    typeof info.bundleId !== 'string' ||
    typeof info.appVersion !== 'string' ||
    typeof info.appBuild !== 'string' ||
    typeof info.density !== 'number' ||
    !Number.isFinite(info.density) ||
    typeof info.locale !== 'string' ||
    typeof info.isTablet !== 'boolean' ||
    typeof info.isFoldable !== 'boolean'
  ) {
    throw new Error('Device returned an invalid payload');
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
    throw new Error('Device returned invalid safe-area insets');
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
    throw new Error('Device returned invalid safe-area insets');
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
      requireDeviceModule().getInfo((resultValue) => {
        'background only';
        try {
          const result = decodeNativeEnvelope(
            resultValue,
            'Device',
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
      requireDeviceModule().getSafeAreaInsets((resultValue) => {
        'background only';
        try {
          const result = decodeNativeEnvelope(resultValue, 'Device');
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

/** Reads the Android status-bar inset without display-cutout expansion. */
export function readStatusBarInsetTop(
  initData: InitData | null | undefined,
): number {
  return normalizeInset(initData?.nativeEnvironment?.statusBarInsetTop);
}

/** Reads the stable Android bottom navigation-bar inset. */
export function readNavigationBarInsetBottom(
  initData: InitData | null | undefined,
): number {
  return normalizeInset(initData?.nativeEnvironment?.navigationBarInsetBottom);
}

/** Reads the first-frame/reactive system appearance injected by the host. */
export function readColorScheme(
  initData: InitData | null | undefined,
): ColorScheme {
  return initData?.nativeEnvironment?.colorScheme === 'dark' ? 'dark' : 'light';
}

/**
 * Resolves the app's supported locale from the host BCP-47 tag. Chinese
 * variants intentionally share the Simplified Chinese resource bundle;
 * unsupported or missing locales fall back to the English base resources.
 */
export function readAppLocale(
  initData: InitData | null | undefined,
): AppLocale {
  const locale = initData?.nativeEnvironment?.locale?.toLowerCase();
  return locale?.startsWith('zh') ? 'zh-Hans' : 'en';
}

/** Controls the foreground color of the current native status bar. */
export const statusBar = {
  setStyle(style: StatusBarStyle): Promise<void> {
    'background only';
    const normalized = normalizeStatusBarStyle(style);
    return completeNativeCall((callback) =>
      requireDeviceModule().setStatusBarStyle(normalized, callback),
    );
  },
};

/**
 * Opens this app's page in the system Settings app (the "app info" screen
 * with permissions, storage and notifications). The canonical escape hatch
 * after a permission has been denied — further settings pages are not
 * reachable through public APIs on iOS / HarmonyOS.
 */
export const appSettings = {
  open(): Promise<void> {
    'background only';
    return completeNativeCall((callback) =>
      requireDeviceModule().openAppSettings(callback),
    );
  },
};

// ---------------------------------------------------------------------------
// Display metrics
// ---------------------------------------------------------------------------

function queryNumber(
  label: string,
  action: (
    module: ReturnType<typeof requireDeviceModule>,
    callback: (result: unknown) => void,
  ) => void,
): Promise<number> {
  'background only';
  return new Promise((resolve, reject) => {
    action(requireDeviceModule(), (resultValue) => {
      'background only';
      try {
        const result = decodeNativeEnvelope(resultValue, label);
        if (typeof result.error === 'string' && result.error.length > 0) {
          reject(new Error(result.error));
          return;
        }
        if (
          typeof result.value !== 'number' ||
          !Number.isFinite(result.value)
        ) {
          throw new Error(`${label} returned an invalid value`);
        }
        resolve(result.value);
      } catch (error) {
        reject(error instanceof Error ? error : new Error(String(error)));
      }
    });
  });
}

/**
 * On-demand display metrics. All widths are Lynx logical pixels
 * (dp/pt/vp) — the unit Lynx layout consumes.
 */
export const display = {
  /** Full screen width, ignoring multi-window or split-screen sizing. */
  screenWidth(): Promise<number> {
    'background only';
    return queryNumber('Display.screenWidth', (module, callback) =>
      module.screenWidth(callback),
    );
  },

  /** Width of the window the app currently occupies. */
  windowWidth(): Promise<number> {
    'background only';
    return queryNumber('Display.windowWidth', (module, callback) =>
      module.windowWidth(callback),
    );
  },

  /**
   * Width of the LynxView rendering this bundle. Resolves to 0 while the
   * view has not been laid out yet, and rejects when no LynxView is
   * attached (or the host cannot measure it).
   */
  lynxViewWidth(): Promise<number> {
    'background only';
    return queryNumber('Display.lynxViewWidth', (module, callback) =>
      module.lynxViewWidth(callback),
    );
  },

  /**
   * Current screen brightness, 0..1. Window-scoped: when the app has
   * overridden the brightness that value is reported, otherwise the system
   * brightness.
   */
  getBrightness(): Promise<number> {
    'background only';
    return queryNumber('Display.getBrightness', (module, callback) =>
      module.getBrightness(callback),
    );
  },

  /**
   * Sets the window brightness (0..1). Applies while the app is visible;
   * the system restores the previous brightness afterwards. Rejects when
   * the host cannot reach a window.
   */
  setBrightness(value: number): Promise<void> {
    'background only';
    if (
      typeof value !== 'number' ||
      !Number.isFinite(value) ||
      value < 0 ||
      value > 1
    ) {
      return Promise.reject(new Error('Brightness must be between 0 and 1'));
    }
    return completeNativeCall((callback) =>
      requireDeviceModule().setBrightness(value, callback),
    );
  },

  /**
   * Keeps the screen on (or restores the system sleep behaviour) while the
   * app is visible. Needs no permission on any platform.
   */
  setKeepScreenOn(enabled: boolean): Promise<void> {
    'background only';
    return completeNativeCall((callback) =>
      requireDeviceModule().setKeepScreenOn(enabled, callback),
    );
  },
};

// ---------------------------------------------------------------------------
// Battery
// ---------------------------------------------------------------------------

/** Battery state reported by the native Device module. */
export interface BatteryInfo {
  /** State of charge 0..1; null when the host cannot read it (e.g. iOS simulator). */
  level: number | null;
  /** True while connected to power and charging or full. */
  charging: boolean;
}

interface BatteryResult {
  error?: unknown;
  value?: unknown;
}

function decodeBatteryInfo(value: unknown): BatteryInfo {
  'background only';
  if (typeof value !== 'object' || value === null) {
    throw new Error('Device returned an invalid battery payload');
  }
  const info = value as Partial<BatteryInfo>;
  const levelValid =
    info.level === null ||
    (typeof info.level === 'number' && Number.isFinite(info.level));
  if (!levelValid || typeof info.charging !== 'boolean') {
    throw new Error('Device returned an invalid battery payload');
  }
  return info as BatteryInfo;
}

export const battery = {
  /** Reads the current battery level and charging state on demand. */
  getInfo(): Promise<BatteryInfo> {
    'background only';
    return new Promise((resolve, reject) => {
      requireDeviceModule().getBatteryInfo((resultValue) => {
        'background only';
        try {
          const result = validateNativeEnvelope(
            resultValue,
            'Device',
          ) as BatteryResult;
          if (typeof result.error === 'string' && result.error.length > 0) {
            reject(new Error(result.error));
            return;
          }
          resolve(decodeBatteryInfo(result.value));
        } catch (error) {
          reject(error instanceof Error ? error : new Error(String(error)));
        }
      });
    });
  },
};

// ---------------------------------------------------------------------------
// Sensors
// ---------------------------------------------------------------------------

export type SensorType =
  | 'accelerometer'
  | 'compass'
  | 'gyroscope'
  | 'magnetometer'
  | 'barometer';

/** Acceleration in m/s^2 including gravity, in the device frame. */
export interface AccelerometerReading {
  type: 'accelerometer';
  x: number;
  y: number;
  z: number;
  /** Approximate emit time, epoch milliseconds. */
  timestamp: number;
}

/** Magnetic-north heading in degrees (0-360). */
export interface CompassReading {
  type: 'compass';
  heading: number;
  /** Estimated uncertainty in degrees; -1 when unreliable. */
  accuracy: number;
  timestamp: number;
}

/** Angular rotation rate in rad/s around the device-frame axes. */
export interface GyroscopeReading {
  type: 'gyroscope';
  x: number;
  y: number;
  z: number;
  timestamp: number;
}

/** Geomagnetic field strength in microtesla, in the device frame. */
export interface MagnetometerReading {
  type: 'magnetometer';
  x: number;
  y: number;
  z: number;
  timestamp: number;
}

/** Ambient barometric pressure in hectopascals (millibars). */
export interface BarometerReading {
  type: 'barometer';
  pressure: number;
  timestamp: number;
}

export type SensorReading =
  | AccelerometerReading
  | CompassReading
  | GyroscopeReading
  | MagnetometerReading
  | BarometerReading;

const SENSOR_TYPES: readonly SensorType[] = [
  'accelerometer',
  'compass',
  'gyroscope',
  'magnetometer',
  'barometer',
];

interface SensorEventPayload {
  type?: unknown;
  x?: unknown;
  y?: unknown;
  z?: unknown;
  heading?: unknown;
  accuracy?: unknown;
  pressure?: unknown;
  timestamp?: unknown;
  error?: unknown;
}

interface SensorListener {
  onReading: (reading: SensorReading) => void;
  onError?: (message: string) => void;
}

interface AvailabilityResult {
  error?: unknown;
  value?: unknown;
}

export const SENSORS_EVENT = 'sensors';

const listeners = new Map<SensorType, Set<SensorListener>>();
let listeningForEvents = false;

function installEventListener(): void {
  'background only';
  if (listeningForEvents) return;
  listeningForEvents = true;
  lynx
    .getJSModule('GlobalEventEmitter')
    .addListener(SENSORS_EVENT, dispatchEvent);
}

function dispatchEvent(value: unknown): void {
  'background only';
  if (typeof value !== 'object' || value === null) return;
  const payload = value as SensorEventPayload;
  if (
    typeof payload.type !== 'string' ||
    !SENSOR_TYPES.includes(payload.type as SensorType)
  ) {
    return;
  }
  const type = payload.type as SensorType;
  if (typeof payload.error === 'string' && payload.error.length > 0) {
    for (const listener of [...(listeners.get(type) ?? [])]) {
      listener.onError?.(payload.error);
    }
    return;
  }
  const reading = decodeReading(type, payload);
  if (reading === null) return;
  for (const listener of [...(listeners.get(type) ?? [])]) {
    listener.onReading(reading);
  }
}

function decodeReading(
  type: SensorType,
  payload: SensorEventPayload,
): SensorReading | null {
  'background only';
  const timestamp =
    typeof payload.timestamp === 'number' && Number.isFinite(payload.timestamp)
      ? payload.timestamp
      : Date.now();
  if (
    type === 'accelerometer' ||
    type === 'gyroscope' ||
    type === 'magnetometer'
  ) {
    if (
      !isFiniteNumber(payload.x) ||
      !isFiniteNumber(payload.y) ||
      !isFiniteNumber(payload.z)
    ) {
      return null;
    }
    return { type, x: payload.x, y: payload.y, z: payload.z, timestamp };
  }
  if (type === 'compass') {
    if (!isFiniteNumber(payload.heading)) {
      return null;
    }
    return {
      type: 'compass',
      heading: payload.heading,
      accuracy: isFiniteNumber(payload.accuracy) ? payload.accuracy : -1,
      timestamp,
    };
  }
  if (!isFiniteNumber(payload.pressure)) {
    return null;
  }
  return { type: 'barometer', pressure: payload.pressure, timestamp };
}

function isFiniteNumber(value: unknown): value is number {
  return typeof value === 'number' && Number.isFinite(value);
}

/** Resolves after a command-style method (error-string ack) succeeds. */
function command(
  action: (
    module: ReturnType<typeof requireDeviceModule>,
    callback: (error: string) => void,
  ) => void,
): Promise<void> {
  'background only';
  return completeNativeCall((callback) =>
    action(requireDeviceModule(), callback),
  );
}

/**
 * Streaming sensors (accelerometer, compass, gyroscope, magnetometer and
 * barometer). Readings arrive through the Lynx GlobalEventEmitter on the
 * `sensors` event; the module keeps each sensor registered only while at
 * least one observer is attached.
 */
export const sensors = {
  /**
   * Whether the device has the requested sensor. `compass` is false on iOS
   * when heading hardware is missing (e.g. Wi-Fi-only iPads, simulators);
   * `barometer` is false on devices without a pressure sensor.
   */
  available(type: SensorType): Promise<boolean> {
    'background only';
    return new Promise((resolve, reject) => {
      requireDeviceModule().isAvailable(type, (resultValue) => {
        'background only';
        try {
          const result = decodeNativeEnvelope(
            resultValue,
            'Device',
          ) as AvailabilityResult;
          if (typeof result.error === 'string' && result.error.length > 0) {
            reject(new Error(result.error));
            return;
          }
          if (typeof result.value !== 'boolean') {
            throw new Error('Device returned an invalid availability');
          }
          resolve(result.value);
        } catch (error) {
          reject(error instanceof Error ? error : new Error(String(error)));
        }
      });
    });
  },

  /**
   * Subscribes to a sensor's readings. The first observer starts the native
   * sensor stream and the last unsubscribe stops it; a failed start (e.g.
   * iOS compass permission denied) is reported through `onError`. Returns
   * an unsubscribe function that is safe to call more than once.
   */
  observe(
    type: SensorType,
    onReading: (reading: SensorReading) => void,
    onError?: (message: string) => void,
  ): () => void {
    'background only';
    installEventListener();
    const entry: SensorListener = { onReading, onError };
    let set = listeners.get(type);
    const startsStream = set === undefined || set.size === 0;
    if (set === undefined) {
      set = new Set();
      listeners.set(type, set);
    }
    set.add(entry);
    if (startsStream) {
      void command((module, callback) => module.start(type, callback)).catch(
        (error: Error) => {
          'background only';
          for (const listener of [...(listeners.get(type) ?? [])]) {
            listener.onError?.(error.message);
          }
        },
      );
    }
    let removed = false;
    return () => {
      'background only';
      if (removed) return;
      removed = true;
      const current = listeners.get(type);
      if (current === undefined) return;
      current.delete(entry);
      if (current.size === 0) {
        listeners.delete(type);
        void command((module, callback) => module.stop(type, callback)).catch(
          () => {},
        );
      }
    };
  },
};
