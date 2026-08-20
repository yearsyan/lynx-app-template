/**
 * Local notifications provided by the native LocalNotification module:
 * immediate and delayed posting plus id-scoped cancellation. Notification
 * permission prompting lives in the separate Permissions module.
 */
import {
  completeNativeCall,
  requireNativeModule,
  validateNativeEnvelope,
} from './bridge.generated.js';

export * from './native.generated.js';

/**
 * Terminal state of one notify request. `permissionDenied` resolves (it is
 * a user-flow state, not a failure): the notification was dropped because
 * notifications are disabled for the app.
 */
export type NotifyOutcomeCode = 'success' | 'permissionDenied' | 'unavailable';

export interface NotifyOutcome {
  /** Convenience flag, always `code === 'success'`. */
  readonly success: boolean;
  readonly code: NotifyOutcomeCode;
  /** Native diagnostic; intended for logging, not for user display. */
  readonly message: string;
}

export interface LocalNotificationOptions {
  /**
   * Caller-scoped stable id used to replace or cancel the notification;
   * reusing an id replaces the previously posted one.
   */
  id: string;
  title: string;
  /** Defaults to an empty string. */
  body?: string;
  /**
   * Delivery delay in milliseconds; 0 (the default) posts immediately.
   * Android schedules through AlarmManager (survives process death),
   * iOS through UNNotificationRequest triggers; HarmonyOS uses in-process
   * timers, so pending delays do not outlive the app process there.
   * Upper bound: 7 days.
   */
  delayMs?: number;
  /** Plays the default notification sound; defaults to true. */
  sound?: boolean;
}

const MAX_DELAY_MS = 7 * 24 * 60 * 60 * 1000;
const KNOWN_CODES: readonly NotifyOutcomeCode[] = [
  'success',
  'permissionDenied',
  'unavailable',
];

function requireLocalNotificationModule() {
  'background only';
  return requireNativeModule();
}

interface NotifyEnvelope {
  error?: string;
  value?: { code?: string; message?: string };
}

function parseOutcome(result: unknown): NotifyOutcome {
  'background only';
  const parsed = validateNativeEnvelope(
    result,
    'LocalNotification',
  ) as NotifyEnvelope;
  if (typeof parsed.error === 'string' && parsed.error.length > 0) {
    throw new Error(parsed.error);
  }
  const code = parsed.value?.code;
  if (code === undefined || !KNOWN_CODES.includes(code as NotifyOutcomeCode)) {
    throw new Error(
      `LocalNotification returned an unknown outcome: ${String(code)}`,
    );
  }
  return {
    success: code === 'success',
    code: code as NotifyOutcomeCode,
    message: parsed.value?.message ?? '',
  };
}

interface NativeLocalNotificationOptions {
  id: string;
  title: string;
  body: string;
  delayMs: number;
  sound: boolean;
}

function normalizeOptions(
  options: LocalNotificationOptions,
): NativeLocalNotificationOptions {
  'background only';
  if (typeof options.id !== 'string' || options.id.trim().length === 0) {
    throw new Error('LocalNotification id must be a non-empty string');
  }
  if (typeof options.title !== 'string' || options.title.trim().length === 0) {
    throw new Error('LocalNotification title must be a non-empty string');
  }
  const delayMs = options.delayMs ?? 0;
  if (!Number.isInteger(delayMs) || delayMs < 0 || delayMs > MAX_DELAY_MS) {
    throw new Error(
      `LocalNotification delayMs must be an integer from 0 to ${MAX_DELAY_MS}`,
    );
  }
  return {
    id: options.id,
    title: options.title,
    body: options.body ?? '',
    delayMs,
    sound: options.sound ?? true,
  };
}

export const localNotification = {
  /**
   * Posts (or schedules) one local notification. Resolves with the
   * outcome; `permissionDenied` means notifications are disabled for the
   * app — ask through `permissions.request('notifications')` or send the
   * user to system settings.
   */
  notify(options: LocalNotificationOptions): Promise<NotifyOutcome> {
    'background only';
    const normalized = normalizeOptions(options);
    return new Promise((resolve, reject) => {
      requireLocalNotificationModule().notify(normalized, (result) => {
        'background only';
        try {
          resolve(parseOutcome(result));
        } catch (error) {
          reject(error instanceof Error ? error : new Error(String(error)));
        }
      });
    });
  },

  /** Cancels the pending schedule and delivered notification for one id. */
  cancel(id: string): Promise<void> {
    'background only';
    if (typeof id !== 'string' || id.trim().length === 0) {
      throw new Error('LocalNotification id must be a non-empty string');
    }
    return completeNativeCall((callback) =>
      requireLocalNotificationModule().cancel(id, callback),
    );
  },

  /** Cancels every notification this app posted or scheduled. */
  cancelAll(): Promise<void> {
    'background only';
    return completeNativeCall((callback) =>
      requireLocalNotificationModule().cancelAll(callback),
    );
  },
};
