/**
 * Streaming motion sensors (accelerometer and compass) from the native
 * Sensors module. Readings arrive through the Lynx GlobalEventEmitter on the
 * `sensors` event; the module keeps each sensor registered only while at
 * least one observer is attached.
 */
import { NATIVE_MODULE_NAMES } from '@lynx-app/native-contracts';
import { requireNativeModule } from './moduleRegistry.js';

export type SensorType = 'accelerometer' | 'compass';

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

export type SensorReading = AccelerometerReading | CompassReading;

interface SensorEventPayload {
  type?: unknown;
  x?: unknown;
  y?: unknown;
  z?: unknown;
  heading?: unknown;
  accuracy?: unknown;
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

function requireSensorsModule() {
  'background only';
  return requireNativeModule(NATIVE_MODULE_NAMES.Sensors);
}

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
  if (payload.type !== 'accelerometer' && payload.type !== 'compass') return;
  const type = payload.type;
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
  type: 'accelerometer' | 'compass',
  payload: SensorEventPayload,
): SensorReading | null {
  'background only';
  const timestamp =
    typeof payload.timestamp === 'number' && Number.isFinite(payload.timestamp)
      ? payload.timestamp
      : Date.now();
  if (type === 'accelerometer') {
    if (
      !isFiniteNumber(payload.x) ||
      !isFiniteNumber(payload.y) ||
      !isFiniteNumber(payload.z)
    ) {
      return null;
    }
    return {
      type: 'accelerometer',
      x: payload.x,
      y: payload.y,
      z: payload.z,
      timestamp,
    };
  }
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

function isFiniteNumber(value: unknown): value is number {
  return typeof value === 'number' && Number.isFinite(value);
}

/** Resolves after a command-style method (error-string ack) succeeds. */
function command(
  action: (
    module: NonNullable<ReturnType<typeof requireSensorsModule>>,
    callback: (error: string) => void,
  ) => void,
): Promise<void> {
  'background only';
  return new Promise((resolve, reject) => {
    action(requireSensorsModule(), (error) => {
      'background only';
      if (error.length > 0) {
        reject(new Error(error));
        return;
      }
      resolve();
    });
  });
}

export const sensors = {
  /**
   * Whether the device has the requested sensor. `compass` is false on iOS
   * when heading hardware is missing (e.g. Wi-Fi-only iPads, simulators).
   */
  available(type: SensorType): Promise<boolean> {
    'background only';
    return new Promise((resolve, reject) => {
      requireSensorsModule().isAvailable(type, (resultJSON) => {
        'background only';
        try {
          if (typeof resultJSON !== 'string') {
            throw new Error('Sensors returned a non-string result');
          }
          const parsed = JSON.parse(resultJSON) as unknown;
          if (typeof parsed !== 'object' || parsed === null) {
            throw new Error('Sensors returned an invalid result');
          }
          const result = parsed as AvailabilityResult;
          if (typeof result.error === 'string' && result.error.length > 0) {
            reject(new Error(result.error));
            return;
          }
          if (typeof result.value !== 'boolean') {
            throw new Error('Sensors returned an invalid availability');
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
