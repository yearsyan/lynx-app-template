/**
 * Biometric (face / fingerprint) and device-credential authentication
 * provided by the native Biometric module.
 */
import {
  decodeNativeEnvelope,
  requireNativeModule,
} from '@lynx-app/native-runtime';
import { BIOMETRIC_MODULE_NAME } from './native.generated.js';

export * from './native.generated.js';

/** Hardware biometry kind. Android cannot report it, so it says 'unknown'. */
export type BiometryType = 'face' | 'fingerprint' | 'unknown';

export type BiometricSupportReason =
  | 'ok'
  | 'noHardware'
  | 'notEnrolled'
  | 'locked'
  | 'noDeviceCredential'
  | 'unavailable'
  | 'unknown';

/** Result of the silent capability probe; never shows UI. */
export interface BiometricSupport {
  canAuthenticate: boolean;
  reason: BiometricSupportReason;
  biometryType: BiometryType;
  /** Whether a lock-screen credential (PIN / password / pattern) is set. */
  deviceCredentialSetup: boolean;
}

/**
 * Terminal state of one authentication attempt. Codes reachable through
 * normal user flow ('userCancel', 'userFallback', …) resolve instead of
 * rejecting so business logic can branch without try/catch.
 */
export type AuthenticateOutcomeCode =
  | 'success'
  | 'userCancel'
  | 'userFallback'
  | 'systemCancel'
  | 'appCancel'
  | 'failed'
  | 'notEnrolled'
  | 'locked'
  | 'noDeviceCredential'
  | 'noHardware'
  | 'timeout'
  | 'busy'
  | 'unavailable'
  | 'unknown';

export interface AuthenticateOutcome {
  /** Convenience flag, always `code === 'success'`. */
  readonly success: boolean;
  readonly code: AuthenticateOutcomeCode;
  /** Native diagnostic; intended for logging, not for user display. */
  readonly message: string;
}

export interface AuthenticateOptions {
  /** Prompt title on Android and HarmonyOS; iOS shows no title. */
  title: string;
  /**
   * iOS `localizedReason` (also shown as the Android description).
   * Apple review requires a clear statement of why the app authenticates.
   */
  reason: string;
  /** Android-only subtitle under the title. */
  subtitle?: string;
  /** Android negative button / iOS fallback button label. */
  cancelButtonText?: string;
  /**
   * Allow the lock-screen credential (PIN / password / pattern) as a
   * fallback when biometrics fail or are not enrolled. Default `false`,
   * which surfaces the fallback as an explicit 'userFallback' outcome so
   * business code keeps control of the password flow.
   */
  allowDeviceCredential?: boolean;
}

/**
 * Outcome of the server-verifiable signing APIs. Extends the prompt
 * outcomes with codes specific to the hardware-bound signing key.
 */
export type CryptoOutcomeCode =
  | AuthenticateOutcomeCode
  /** No hardware-backed, biometric-gated key support (e.g. no Class 3 sensor). */
  | 'notSupported'
  /** No signing key on this device; call createSigningKey() first. */
  | 'keyNotFound';

export interface CreateSigningKeyResult {
  /** Convenience flag, always `code === 'success'`. */
  readonly success: boolean;
  readonly code: CryptoOutcomeCode;
  readonly message: string;
  /**
   * Base64 of the 65-byte uncompressed EC P-256 point (0x04 || X || Y)
   * when successful; register it with the server. `null` otherwise.
   */
  readonly publicKey: string | null;
}

export interface SignChallengeResult {
  /** Convenience flag, always `code === 'success'`. */
  readonly success: boolean;
  readonly code: CryptoOutcomeCode;
  readonly message: string;
  /**
   * Base64 of the 64-byte ECDSA signature (raw r || s, IEEE P1363) when
   * successful; `null` otherwise.
   */
  readonly signature: string | null;
}

export interface SignChallengeOptions {
  /**
   * Base64 of the server-issued one-time nonce to sign. The server must
   * verify both the signature and the nonce's freshness.
   */
  challenge: string;
  /** Prompt title on Android and HarmonyOS; iOS shows no title. */
  title: string;
  /** iOS `localizedReason` / Android description shown in the prompt. */
  reason: string;
  /** Android-only subtitle under the title. */
  subtitle?: string;
  /** Android negative button / iOS fallback button label. */
  cancelButtonText?: string;
}

interface BiometricEnvelope {
  error?: unknown;
  value?: unknown;
}

function requireBiometricModule() {
  'background only';
  return requireNativeModule(BIOMETRIC_MODULE_NAME);
}

function decodeEnvelope(result: unknown): BiometricEnvelope {
  'background only';
  return decodeNativeEnvelope(result, 'Biometric') as BiometricEnvelope;
}

function decodeSupport(value: unknown): BiometricSupport {
  'background only';
  if (typeof value !== 'object' || value === null) {
    throw new Error('Biometric returned an invalid support payload');
  }
  const support = value as Partial<BiometricSupport>;
  const biometryType = support.biometryType;
  const reason = support.reason;
  if (
    typeof support.canAuthenticate !== 'boolean' ||
    typeof support.deviceCredentialSetup !== 'boolean' ||
    (biometryType !== 'face' &&
      biometryType !== 'fingerprint' &&
      biometryType !== 'unknown') ||
    !isSupportReason(reason)
  ) {
    throw new Error('Biometric returned an invalid support payload');
  }
  return {
    canAuthenticate: support.canAuthenticate,
    reason,
    biometryType,
    deviceCredentialSetup: support.deviceCredentialSetup,
  };
}

function isSupportReason(value: unknown): value is BiometricSupportReason {
  'background only';
  return (
    value === 'ok' ||
    value === 'noHardware' ||
    value === 'notEnrolled' ||
    value === 'locked' ||
    value === 'noDeviceCredential' ||
    value === 'unavailable' ||
    value === 'unknown'
  );
}

function decodeOutcome(value: unknown): AuthenticateOutcome {
  'background only';
  if (typeof value !== 'object' || value === null) {
    throw new Error('Biometric returned an invalid outcome payload');
  }
  const outcome = value as Partial<AuthenticateOutcome>;
  const code = outcome.code;
  if (!isOutcomeCode(code)) {
    throw new Error('Biometric returned an invalid outcome payload');
  }
  const message = typeof outcome.message === 'string' ? outcome.message : '';
  return { success: code === 'success', code, message };
}

function isOutcomeCode(value: unknown): value is AuthenticateOutcomeCode {
  'background only';
  return (
    value === 'success' ||
    value === 'userCancel' ||
    value === 'userFallback' ||
    value === 'systemCancel' ||
    value === 'appCancel' ||
    value === 'failed' ||
    value === 'notEnrolled' ||
    value === 'locked' ||
    value === 'noDeviceCredential' ||
    value === 'noHardware' ||
    value === 'timeout' ||
    value === 'busy' ||
    value === 'unavailable' ||
    value === 'unknown'
  );
}

function isCryptoCode(value: unknown): value is CryptoOutcomeCode {
  'background only';
  return (
    isOutcomeCode(value) || value === 'notSupported' || value === 'keyNotFound'
  );
}

function decodeCryptoOutcome(value: unknown): {
  code: CryptoOutcomeCode;
  message: string;
} {
  'background only';
  if (typeof value !== 'object' || value === null) {
    throw new Error('Biometric returned an invalid crypto payload');
  }
  const outcome = value as Partial<CreateSigningKeyResult>;
  const code = outcome.code;
  if (!isCryptoCode(code)) {
    throw new Error('Biometric returned an invalid crypto payload');
  }
  return {
    code,
    message: typeof outcome.message === 'string' ? outcome.message : '',
  };
}

const BASE64_PATTERN = /^[A-Za-z0-9+/]+={0,2}$/;

function normalizeSignChallengeOptions(
  options: SignChallengeOptions,
): Record<string, unknown> {
  'background only';
  const title = options.title.trim();
  const reason = options.reason.trim();
  if (title.length === 0) {
    throw new Error('Biometric title must not be empty');
  }
  if (reason.length === 0) {
    throw new Error('Biometric reason must not be empty');
  }
  const challenge = options.challenge.trim();
  if (
    challenge.length === 0 ||
    challenge.length % 4 !== 0 ||
    !BASE64_PATTERN.test(challenge)
  ) {
    throw new Error('Biometric challenge must be non-empty standard Base64');
  }
  const normalized: Record<string, unknown> = { title, reason, challenge };
  const subtitle = options.subtitle?.trim();
  if (subtitle !== undefined && subtitle.length > 0) {
    normalized.subtitle = subtitle;
  }
  const cancelButtonText = options.cancelButtonText?.trim();
  if (cancelButtonText !== undefined && cancelButtonText.length > 0) {
    normalized.cancelButtonText = cancelButtonText;
  }
  return normalized;
}

function normalizeAuthenticateOptions(
  options: AuthenticateOptions,
): Record<string, unknown> {
  'background only';
  const title = options.title.trim();
  const reason = options.reason.trim();
  if (title.length === 0) {
    throw new Error('Biometric title must not be empty');
  }
  if (reason.length === 0) {
    throw new Error('Biometric reason must not be empty');
  }
  const normalized: Record<string, unknown> = {
    title,
    reason,
    allowDeviceCredential: options.allowDeviceCredential ?? false,
  };
  const subtitle = options.subtitle?.trim();
  if (subtitle !== undefined && subtitle.length > 0) {
    normalized.subtitle = subtitle;
  }
  const cancelButtonText = options.cancelButtonText?.trim();
  if (cancelButtonText !== undefined && cancelButtonText.length > 0) {
    normalized.cancelButtonText = cancelButtonText;
  }
  return normalized;
}

export const biometric = {
  /**
   * Silently reports whether the biometric prompt can be shown right now
   * and why not. Use it to decide whether to offer biometric features;
   * it never triggers the system prompt or a permission dialog.
   */
  checkSupport(): Promise<BiometricSupport> {
    'background only';
    return new Promise((resolve, reject) => {
      requireBiometricModule().checkSupport((resultJSON) => {
        'background only';
        try {
          const result = decodeEnvelope(resultJSON);
          if (typeof result.error === 'string' && result.error.length > 0) {
            reject(new Error(result.error));
            return;
          }
          resolve(decodeSupport(result.value));
        } catch (error) {
          reject(error instanceof Error ? error : new Error(String(error)));
        }
      });
    });
  },

  /**
   * Shows the system biometric prompt and resolves with the terminal
   * outcome. Only one request may be active per Lynx page; a second call
   * resolves with code 'busy'. Programmer errors (empty title/reason,
   * missing module) reject or throw.
   */
  authenticate(options: AuthenticateOptions): Promise<AuthenticateOutcome> {
    'background only';
    const normalized = normalizeAuthenticateOptions(options);
    return new Promise((resolve, reject) => {
      requireBiometricModule().authenticate(
        JSON.stringify(normalized),
        (resultJSON) => {
          'background only';
          try {
            const result = decodeEnvelope(resultJSON);
            if (typeof result.error === 'string' && result.error.length > 0) {
              reject(new Error(result.error));
              return;
            }
            resolve(decodeOutcome(result.value));
          } catch (error) {
            reject(error instanceof Error ? error : new Error(String(error)));
          }
        },
      );
    });
  },

  /**
   * Generates (or replaces) this app's hardware-bound EC P-256 signing key.
   * The private key never leaves secure hardware and can only be used after
   * a successful biometric prompt. No prompt is shown by this call itself.
   * Send the returned `publicKey` to the server and bind it to the account.
   */
  createSigningKey(): Promise<CreateSigningKeyResult> {
    'background only';
    return new Promise((resolve, reject) => {
      requireBiometricModule().createSigningKey((resultJSON) => {
        'background only';
        try {
          const result = decodeEnvelope(resultJSON);
          if (typeof result.error === 'string' && result.error.length > 0) {
            reject(new Error(result.error));
            return;
          }
          const decoded = decodeCryptoOutcome(result.value);
          const payload =
            result.value as Partial<CreateSigningKeyResult> | null;
          const publicKey =
            typeof payload?.publicKey === 'string' ? payload.publicKey : null;
          resolve({
            success: decoded.code === 'success',
            code: decoded.code,
            message: decoded.message,
            publicKey: decoded.code === 'success' ? publicKey : null,
          });
        } catch (error) {
          reject(error instanceof Error ? error : new Error(String(error)));
        }
      });
    });
  },

  /**
   * Signs a server-issued Base64 challenge with the biometric-gated key,
   * showing the system prompt first. Resolves with the Base64 signature
   * (64-byte r || s); user-facing outcomes (cancel, fallback, lockout)
   * resolve with their code and `signature: null`. Requires a key from
   * createSigningKey(); otherwise resolves with code 'keyNotFound'.
   * Biometric re-enrollment invalidates the key — handle 'keyNotFound' by
   * re-creating the key and re-registering the public key with the server.
   */
  signChallenge(options: SignChallengeOptions): Promise<SignChallengeResult> {
    'background only';
    const normalized = normalizeSignChallengeOptions(options);
    return new Promise((resolve, reject) => {
      requireBiometricModule().signChallenge(
        JSON.stringify(normalized),
        (resultJSON) => {
          'background only';
          try {
            const result = decodeEnvelope(resultJSON);
            if (typeof result.error === 'string' && result.error.length > 0) {
              reject(new Error(result.error));
              return;
            }
            const decoded = decodeCryptoOutcome(result.value);
            const payload = result.value as Partial<SignChallengeResult> | null;
            const signature =
              typeof payload?.signature === 'string' ? payload.signature : null;
            resolve({
              success: decoded.code === 'success',
              code: decoded.code,
              message: decoded.message,
              signature: decoded.code === 'success' ? signature : null,
            });
          } catch (error) {
            reject(error instanceof Error ? error : new Error(String(error)));
          }
        },
      );
    });
  },
};
