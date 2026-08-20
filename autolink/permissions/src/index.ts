/**
 * Unified runtime permission checks and prompts provided by the native
 * Permissions module (notifications, camera, photo library, microphone).
 */
import {
  requireNativeModule,
  validateNativeEnvelope,
} from './bridge.generated.js';

export * from './native.generated.js';

/** Permission families exposed through the shared check/request contract. */
export type PermissionType =
  | 'notifications'
  | 'camera'
  | 'photoLibrary'
  | 'microphone';

/**
 * Normalized permission state across the three hosts.
 *
 * - `granted`: allowed.
 * - `limited`: partial photo-library access ("Select photos" on Android 14+
 *   and iOS 14+); behaves like `granted` for pickers.
 * - `denied`: refused, or (Android) simply not granted yet — Android cannot
 *   distinguish "never asked" from "don't ask again", so `request` may still
 *   show the system prompt after a `denied` answer.
 * - `notDetermined`: never asked; `request` shows the prompt.
 * - `restricted`: blocked by system policy (parental controls / MDM).
 */
export type PermissionStatus =
  | 'granted'
  | 'limited'
  | 'denied'
  | 'notDetermined'
  | 'restricted';

export interface PermissionState {
  readonly status: PermissionStatus;
}

const PERMISSION_TYPES: readonly PermissionType[] = [
  'notifications',
  'camera',
  'photoLibrary',
  'microphone',
];

const KNOWN_STATUSES: readonly PermissionStatus[] = [
  'granted',
  'limited',
  'denied',
  'notDetermined',
  'restricted',
];

function requirePermissionsModule() {
  'background only';
  return requireNativeModule();
}

function assertType(type: PermissionType): void {
  'background only';
  if (!PERMISSION_TYPES.includes(type)) {
    throw new Error(
      `Permissions type must be one of ${PERMISSION_TYPES.join(', ')}: ${String(type)}`,
    );
  }
}

interface PermissionsEnvelope {
  error?: string;
  value?: { status?: string };
}

function parseState(result: unknown): PermissionState {
  'background only';
  const parsed = validateNativeEnvelope(
    result,
    'Permissions',
  ) as PermissionsEnvelope;
  if (typeof parsed.error === 'string' && parsed.error.length > 0) {
    throw new Error(parsed.error);
  }
  const status = parsed.value?.status;
  if (
    status === undefined ||
    !KNOWN_STATUSES.includes(status as PermissionStatus)
  ) {
    throw new Error(
      `Permissions returned an unknown status: ${String(status)}`,
    );
  }
  return { status: status as PermissionStatus };
}

function run(
  kind: 'check' | 'request',
  type: PermissionType,
): Promise<PermissionState> {
  'background only';
  assertType(type);
  const permission = { type };
  return new Promise((resolve, reject) => {
    const callback = (result: unknown) => {
      'background only';
      try {
        resolve(parseState(result));
      } catch (error) {
        reject(error instanceof Error ? error : new Error(String(error)));
      }
    };
    if (kind === 'check') {
      requirePermissionsModule().check(permission, callback);
    } else {
      requirePermissionsModule().request(permission, callback);
    }
  });
}

export const permissions = {
  /**
   * Reads the current state without showing any UI. Resolve-and-branch
   * instead of caching: Android answers may change with app settings.
   */
  check(type: PermissionType): Promise<PermissionState> {
    'background only';
    return run('check', type);
  },

  /**
   * Shows the system prompt when the permission is not granted yet and
   * resolves with the resulting state. A user refusal resolves with
   * `denied` instead of rejecting; only invalid input and host errors
   * reject.
   */
  request(type: PermissionType): Promise<PermissionState> {
    'background only';
    return run('request', type);
  },
};
