import { NATIVE_MODULE_NAMES } from '@lynx-app/native-contracts';
import { requireNativeModule } from './moduleRegistry.js';

/** Battery state reported by the native Battery module. */
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

function requireBatteryModule() {
  'background only';
  return requireNativeModule(NATIVE_MODULE_NAMES.Battery);
}

function decodeBatteryInfo(value: unknown): BatteryInfo {
  'background only';
  if (typeof value !== 'object' || value === null) {
    throw new Error('Battery returned an invalid payload');
  }
  const info = value as Partial<BatteryInfo>;
  const levelValid =
    info.level === null ||
    (typeof info.level === 'number' && Number.isFinite(info.level));
  if (!levelValid || typeof info.charging !== 'boolean') {
    throw new Error('Battery returned an invalid payload');
  }
  return info as BatteryInfo;
}

export const battery = {
  /** Reads the current battery level and charging state on demand. */
  getInfo(): Promise<BatteryInfo> {
    'background only';
    return new Promise((resolve, reject) => {
      requireBatteryModule().getInfo((resultJSON) => {
        'background only';
        try {
          if (typeof resultJSON !== 'string') {
            throw new Error('Battery returned a non-string result');
          }
          const parsed = JSON.parse(resultJSON) as unknown;
          if (typeof parsed !== 'object' || parsed === null) {
            throw new Error('Battery returned an invalid result');
          }
          const result = parsed as BatteryResult;
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
