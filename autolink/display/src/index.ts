/**
 * On-demand display metrics from the native Display module. All widths are
 * Lynx logical pixels (dp/pt/vp) — the unit Lynx layout consumes.
 */
import {
  completeNativeCall,
  decodeNativeEnvelope,
  requireNativeModule,
} from '@lynx-app/native-runtime';
import { DISPLAY_MODULE_NAME, type DisplayModule } from './native.generated.js';

export * from './native.generated.js';

interface DisplayResult {
  error?: unknown;
  value?: unknown;
}

function requireDisplayModule(): DisplayModule {
  'background only';
  return requireNativeModule(DISPLAY_MODULE_NAME);
}

function queryWidth(
  label: string,
  action: (module: DisplayModule, callback: (result: unknown) => void) => void,
): Promise<number> {
  'background only';
  return new Promise((resolve, reject) => {
    action(requireDisplayModule(), (resultValue) => {
      'background only';
      try {
        const result = decodeNativeEnvelope(
          resultValue,
          label,
        ) as DisplayResult;
        if (typeof result.error === 'string' && result.error.length > 0) {
          reject(new Error(result.error));
          return;
        }
        if (
          typeof result.value !== 'number' ||
          !Number.isFinite(result.value)
        ) {
          throw new Error(`${label} returned an invalid width`);
        }
        resolve(result.value);
      } catch (error) {
        reject(error instanceof Error ? error : new Error(String(error)));
      }
    });
  });
}

/** Resolves after a command-style method (error-string ack) succeeds. */
function command(
  action: (module: DisplayModule, callback: (error: string) => void) => void,
): Promise<void> {
  'background only';
  return completeNativeCall((callback) =>
    action(requireDisplayModule(), callback),
  );
}

export const display = {
  /** Full screen width, ignoring multi-window or split-screen sizing. */
  screenWidth(): Promise<number> {
    'background only';
    return queryWidth('Display.screenWidth', (module, callback) =>
      module.screenWidth(callback),
    );
  },

  /** Width of the window the app currently occupies. */
  windowWidth(): Promise<number> {
    'background only';
    return queryWidth('Display.windowWidth', (module, callback) =>
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
    return queryWidth('Display.lynxViewWidth', (module, callback) =>
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
    return queryWidth('Display.getBrightness', (module, callback) =>
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
    return command((module, callback) => module.setBrightness(value, callback));
  },

  /**
   * Keeps the screen on (or restores the system sleep behaviour) while the
   * app is visible. Needs no permission on any platform.
   */
  setKeepScreenOn(enabled: boolean): Promise<void> {
    'background only';
    return command((module, callback) =>
      module.setKeepScreenOn(enabled, callback),
    );
  },
};
