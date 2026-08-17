/**
 * Native toast notifications rendered inside the app's own window on every
 * platform — never through the system toast/notification pipeline — so they
 * keep the app's custom styling in any system theme and do not require
 * notification permission.
 */

export type ToastType = 'info' | 'success' | 'error';

export interface ToastOptions {
  /** Semantic type; picks the built-in icon. Defaults to 'info'. */
  type?: ToastType;
  /** Defaults to true. On HarmonyOS the icon is a text prefix. */
  showIcon?: boolean;
  /** Bubble color as `#RRGGBB` or `#AARRGGBB`; defaults to opaque dark. */
  backgroundColor?: string;
  /** Message color as `#RRGGBB` or `#AARRGGBB`; defaults to white. */
  textColor?: string;
  /**
   * Defaults to 2000ms. Android and iOS honor it exactly; HarmonyOS clamps
   * to the system toast window (1500–10000ms).
   */
  durationMs?: number;
}

interface NormalizedToastOptions {
  type: ToastType;
  showIcon: boolean;
  backgroundColor?: string;
  textColor?: string;
  durationMs: number;
}

interface ToastModule {
  show(
    message: string,
    options: NormalizedToastOptions,
    callback: (error: string) => void,
  ): void;
}

interface AppModules {
  Toast?: ToastModule;
}

const DEFAULT_DURATION_MS = 2000;
const MIN_DURATION_MS = 500;
const MAX_DURATION_MS = 10000;
const MAX_MESSAGE_LENGTH = 200;
const COLOR_PATTERN = /^#(?:[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/;

function requireToastModule(): ToastModule {
  'background only';
  const module = (NativeModules as AppModules).Toast;
  if (module === undefined) {
    throw new Error('Toast is not registered by the host');
  }
  return module;
}

function validateColor(
  value: string | undefined,
  label: string,
): string | undefined {
  'background only';
  if (value === undefined) {
    return undefined;
  }
  if (!COLOR_PATTERN.test(value)) {
    throw new Error(
      `Toast ${label} must be a #RRGGBB or #AARRGGBB string: ${value}`,
    );
  }
  return value;
}

function normalizeOptions(options: ToastOptions): NormalizedToastOptions {
  'background only';
  const type = options.type ?? 'info';
  if (type !== 'info' && type !== 'success' && type !== 'error') {
    throw new Error(`Invalid toast type: ${String(type)}`);
  }
  const durationMs = options.durationMs ?? DEFAULT_DURATION_MS;
  if (
    !Number.isInteger(durationMs) ||
    durationMs < MIN_DURATION_MS ||
    durationMs > MAX_DURATION_MS
  ) {
    throw new Error(
      `Toast durationMs must be an integer from ${MIN_DURATION_MS} to ${MAX_DURATION_MS}`,
    );
  }
  return {
    type,
    showIcon: options.showIcon ?? true,
    backgroundColor: validateColor(options.backgroundColor, 'backgroundColor'),
    textColor: validateColor(options.textColor, 'textColor'),
    durationMs,
  };
}

export const toast = {
  /**
   * Shows a one-shot native toast. A new toast replaces the previous one
   * instead of queueing.
   */
  show(message: string, options: ToastOptions = {}): Promise<void> {
    'background only';
    if (message.length === 0) {
      throw new Error('Toast message must not be empty');
    }
    if (message.length > MAX_MESSAGE_LENGTH) {
      throw new Error(
        `Toast message is limited to ${MAX_MESSAGE_LENGTH} characters`,
      );
    }
    const normalized = normalizeOptions(options);
    return new Promise((resolve, reject) => {
      requireToastModule().show(message, normalized, (error) => {
        'background only';
        if (error.length > 0) {
          reject(new Error(error));
        } else {
          resolve();
        }
      });
    });
  },

  info(message: string, options: ToastOptions = {}): Promise<void> {
    'background only';
    return this.show(message, { ...options, type: 'info' });
  },

  success(message: string, options: ToastOptions = {}): Promise<void> {
    'background only';
    return this.show(message, { ...options, type: 'success' });
  },

  error(message: string, options: ToastOptions = {}): Promise<void> {
    'background only';
    return this.show(message, { ...options, type: 'error' });
  },
};
