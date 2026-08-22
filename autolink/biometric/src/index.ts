/** Cross-platform local authentication and biometric-gated signing. */
import {
  decodeNativeEnvelope,
  requireNativeModule,
} from './bridge.generated.js';
import {
  biometricScopeFromKeyId,
  buildBiometricSigningPayload,
  decodeStandardBase64,
  isBiometricKeyId,
  normalizeBiometricScope,
  requireBiometricKeyId,
} from './protocol.js';

export * from './native.generated.js';
export * from './protocol.js';

/** Primary/reportable biometry kind; it is informational, not a selector. */
export type BiometryType = 'face' | 'fingerprint' | 'unknown';

export type LocalAuthenticationPolicy =
  | 'biometricWeak'
  | 'biometricStrong'
  | 'deviceOwnerAuthentication';

export type BiometricSupportReason =
  | 'ok'
  | 'noHardware'
  | 'notEnrolled'
  | 'locked'
  | 'noDeviceCredential'
  | 'unavailable'
  | 'unknown';

export interface CheckSupportOptions {
  /** Defaults to `biometricWeak`. */
  policy?: LocalAuthenticationPolicy;
}

/** Result of the silent capability probe; never shows UI. */
export interface BiometricSupport {
  readonly policy: LocalAuthenticationPolicy;
  readonly canAuthenticate: boolean;
  readonly reason: BiometricSupportReason;
  readonly biometryType: BiometryType;
  readonly deviceCredentialSetup: boolean;
}

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
  readonly success: boolean;
  readonly code: AuthenticateOutcomeCode;
  readonly policy: LocalAuthenticationPolicy;
  /** Native diagnostic intended for logging, not direct user display. */
  readonly message: string;
}

export interface AuthenticateOptions {
  /** Defaults to `biometricWeak`. */
  policy?: LocalAuthenticationPolicy;
  /** Prompt title on Android and HarmonyOS; required but not shown by iOS. */
  title: string;
  /** iOS localizedReason and Android prompt description. */
  reason: string;
  /** Android-only subtitle. */
  subtitle?: string;
  /** Cancel/navigation label where the platform permits customization. */
  cancelButtonText?: string;
}

export type CryptoOutcomeCode =
  | AuthenticateOutcomeCode
  | 'notSupported'
  | 'keyNotFound';

export type SigningKeySecurityLevel = 'secureHardware' | 'software' | 'unknown';

export interface SigningKeyAttestation {
  readonly type: 'androidKey' | 'huks';
  /** Base64 DER certificates/blobs in platform-defined chain order. */
  readonly certificates: readonly string[];
}

export interface CreateSigningKeyOptions {
  /**
   * Opaque, non-PII account/device scope. Allowed characters: A-Z, a-z,
   * 0-9, dot, underscore and hyphen; maximum 64 characters.
   */
  scope: string;
  /**
   * Standard Base64 server challenge decoding to 16..128 bytes for
   * best-effort platform key attestation. Unsupported platforms return
   * `attestation: null`.
   */
  attestationChallenge?: string;
}

export interface SigningKeyResult {
  readonly success: boolean;
  readonly code: CryptoOutcomeCode;
  readonly message: string;
  readonly keyId: string | null;
  readonly scope: string | null;
  /** Base64 65-byte uncompressed P-256 public point. */
  readonly publicKey: string | null;
  readonly algorithm: 'ES256' | null;
  readonly signatureEncoding: 'ieee-p1363' | null;
  readonly securityLevel: SigningKeySecurityLevel;
  readonly attestation: SigningKeyAttestation | null;
}

export interface SigningKeyIdOptions {
  keyId: string;
}

export interface DeleteSigningKeyResult {
  readonly success: boolean;
  readonly code: CryptoOutcomeCode;
  readonly message: string;
  readonly keyId: string;
}

export interface SignChallengeOptions
  extends Omit<AuthenticateOptions, 'policy'> {
  keyId: string;
  /** Standard Base64 server nonce; decoded length must be 16..64 bytes. */
  challenge: string;
  /** Standard Base64 SHA-256 of canonical operation context. */
  contextHash: string;
}

export interface SignChallengeResult {
  readonly success: boolean;
  readonly code: CryptoOutcomeCode;
  readonly message: string;
  readonly keyId: string;
  /** Base64 64-byte ECDSA P1363 `r || s`; null on failure. */
  readonly signature: string | null;
}

interface BiometricEnvelope {
  error?: unknown;
  value?: unknown;
}

interface PromptFields {
  title: string;
  reason: string;
  subtitle?: string;
  cancelButtonText?: string;
}

function requireBiometricModule() {
  'background only';
  return requireNativeModule();
}

function decodeEnvelope(result: unknown): BiometricEnvelope {
  'background only';
  return decodeNativeEnvelope(result, 'Biometric') as BiometricEnvelope;
}

function envelopeValue(resultJSON: unknown): unknown {
  'background only';
  const result = decodeEnvelope(resultJSON);
  if (typeof result.error === 'string' && result.error.length > 0) {
    throw new Error(result.error);
  }
  return result.value;
}

function normalizePolicy(value: unknown): LocalAuthenticationPolicy {
  'background only';
  if (value === undefined) return 'biometricWeak';
  if (
    value === 'biometricWeak' ||
    value === 'biometricStrong' ||
    value === 'deviceOwnerAuthentication'
  ) {
    return value;
  }
  throw new Error('Biometric authentication policy is invalid');
}

function decodeSupport(value: unknown): BiometricSupport {
  'background only';
  if (typeof value !== 'object' || value === null) {
    throw new Error('Biometric returned an invalid support payload');
  }
  const support = value as Partial<BiometricSupport>;
  const policy = normalizePolicy(support.policy);
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
    policy,
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

function decodeOutcome(value: unknown): AuthenticateOutcome {
  'background only';
  if (typeof value !== 'object' || value === null) {
    throw new Error('Biometric returned an invalid outcome payload');
  }
  const outcome = value as Partial<AuthenticateOutcome>;
  if (!isOutcomeCode(outcome.code)) {
    throw new Error('Biometric returned an invalid outcome payload');
  }
  return {
    success: outcome.code === 'success',
    code: outcome.code,
    policy: normalizePolicy(outcome.policy),
    message: typeof outcome.message === 'string' ? outcome.message : '',
  };
}

function decodeCryptoBase(value: unknown): {
  payload: Record<string, unknown>;
  code: CryptoOutcomeCode;
  message: string;
} {
  'background only';
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    throw new Error('Biometric returned an invalid crypto payload');
  }
  const payload = value as Record<string, unknown>;
  const code = payload.code;
  if (!isCryptoCode(code)) {
    throw new Error('Biometric returned an invalid crypto payload');
  }
  return {
    payload,
    code,
    message: typeof payload.message === 'string' ? payload.message : '',
  };
}

function decodeSigningKey(value: unknown): SigningKeyResult {
  'background only';
  const { payload, code, message } = decodeCryptoBase(value);
  if (code !== 'success') {
    return {
      success: false,
      code,
      message,
      keyId: null,
      scope: null,
      publicKey: null,
      algorithm: null,
      signatureEncoding: null,
      securityLevel: 'unknown',
      attestation: null,
    };
  }

  const keyId = requireBiometricKeyId(payload.keyId);
  const scope = biometricScopeFromKeyId(keyId);
  if (payload.scope !== scope) {
    throw new Error('Biometric returned a mismatched key scope');
  }
  const publicKey = payload.publicKey;
  const publicBytes = decodeStandardBase64(publicKey, 'Biometric publicKey');
  if (publicBytes.length !== 65 || publicBytes[0] !== 0x04) {
    throw new Error('Biometric publicKey must be a 65-byte P-256 point');
  }
  const securityLevel = payload.securityLevel;
  if (
    securityLevel !== 'secureHardware' &&
    securityLevel !== 'software' &&
    securityLevel !== 'unknown'
  ) {
    throw new Error('Biometric returned an invalid key security level');
  }

  let attestation: SigningKeyAttestation | null = null;
  if (payload.attestationType !== 'none') {
    if (
      payload.attestationType !== 'androidKey' &&
      payload.attestationType !== 'huks'
    ) {
      throw new Error('Biometric returned an invalid attestation type');
    }
    if (!Array.isArray(payload.attestationCertificates)) {
      throw new Error('Biometric returned an invalid attestation chain');
    }
    const certificates = payload.attestationCertificates.map(
      (certificate, index) => {
        decodeStandardBase64(
          certificate,
          `Biometric attestation certificate ${index}`,
        );
        return certificate as string;
      },
    );
    if (certificates.length === 0) {
      throw new Error('Biometric returned an empty attestation chain');
    }
    attestation = { type: payload.attestationType, certificates };
  }

  return {
    success: true,
    code,
    message,
    keyId,
    scope,
    publicKey: publicKey as string,
    algorithm: 'ES256',
    signatureEncoding: 'ieee-p1363',
    securityLevel,
    attestation,
  };
}

function decodeDeleteResult(
  value: unknown,
  requestedKeyId: string,
): DeleteSigningKeyResult {
  'background only';
  const { payload, code, message } = decodeCryptoBase(value);
  if (payload.keyId !== requestedKeyId) {
    throw new Error('Biometric returned a mismatched deleted keyId');
  }
  return { success: code === 'success', code, message, keyId: requestedKeyId };
}

function decodeSignatureResult(
  value: unknown,
  requestedKeyId: string,
): SignChallengeResult {
  'background only';
  const { payload, code, message } = decodeCryptoBase(value);
  if (payload.keyId !== requestedKeyId) {
    throw new Error('Biometric returned a mismatched signing keyId');
  }
  if (code !== 'success') {
    return {
      success: false,
      code,
      message,
      keyId: requestedKeyId,
      signature: null,
    };
  }
  const signature = payload.signature;
  const bytes = decodeStandardBase64(signature, 'Biometric signature');
  if (bytes.length !== 64) {
    throw new Error('Biometric signature must be 64-byte IEEE P1363');
  }
  return {
    success: true,
    code,
    message,
    keyId: requestedKeyId,
    signature: signature as string,
  };
}

function promptFields(options: AuthenticateOptions): PromptFields {
  'background only';
  if (typeof options !== 'object' || options === null) {
    throw new Error('Biometric options are required');
  }
  const title = options.title?.trim();
  const reason = options.reason?.trim();
  if (!title) throw new Error('Biometric title must not be empty');
  if (!reason) throw new Error('Biometric reason must not be empty');
  if (title.length > 200) throw new Error('Biometric title is too long');
  if (reason.length > 500) throw new Error('Biometric reason is too long');
  const fields: PromptFields = { title, reason };
  const subtitle = options.subtitle?.trim();
  if (subtitle) {
    if (subtitle.length > 200)
      throw new Error('Biometric subtitle is too long');
    fields.subtitle = subtitle;
  }
  const cancelButtonText = options.cancelButtonText?.trim();
  if (cancelButtonText) {
    if (cancelButtonText.length > 60) {
      throw new Error('Biometric cancelButtonText is too long');
    }
    fields.cancelButtonText = cancelButtonText;
  }
  return fields;
}

function callbackPromise<T>(
  invoke: (callback: (resultJSON: unknown) => void) => void,
  decode: (value: unknown) => T,
): Promise<T> {
  'background only';
  return new Promise((resolve, reject) => {
    try {
      invoke((resultJSON) => {
        'background only';
        try {
          resolve(decode(envelopeValue(resultJSON)));
        } catch (error) {
          reject(error instanceof Error ? error : new Error(String(error)));
        }
      });
    } catch (error) {
      reject(error instanceof Error ? error : new Error(String(error)));
    }
  });
}

export const biometric = {
  checkSupport(options: CheckSupportOptions = {}): Promise<BiometricSupport> {
    'background only';
    const policy = normalizePolicy(options.policy);
    return callbackPromise(
      (callback) =>
        requireBiometricModule().checkSupport(
          JSON.stringify({ policy }),
          callback,
        ),
      decodeSupport,
    );
  },

  authenticate(options: AuthenticateOptions): Promise<AuthenticateOutcome> {
    'background only';
    const normalized = {
      ...promptFields(options),
      policy: normalizePolicy(options.policy),
    };
    return callbackPromise(
      (callback) =>
        requireBiometricModule().authenticate(
          JSON.stringify(normalized),
          callback,
        ),
      decodeOutcome,
    );
  },

  /** Creates a new key without deleting any existing key. */
  createSigningKey(
    options: CreateSigningKeyOptions,
  ): Promise<SigningKeyResult> {
    'background only';
    const scope = normalizeBiometricScope(options?.scope);
    const normalized: Record<string, unknown> = { scope };
    if (options.attestationChallenge !== undefined) {
      const challenge = options.attestationChallenge.trim();
      const bytes = decodeStandardBase64(
        challenge,
        'Biometric attestationChallenge',
      );
      if (bytes.length < 16 || bytes.length > 128) {
        throw new Error(
          'Biometric attestationChallenge must decode to 16..128 bytes',
        );
      }
      normalized.attestationChallenge = challenge;
    }
    return callbackPromise(
      (callback) =>
        requireBiometricModule().createSigningKey(
          JSON.stringify(normalized),
          callback,
        ),
      decodeSigningKey,
    );
  },

  getSigningKey(options: SigningKeyIdOptions): Promise<SigningKeyResult> {
    'background only';
    const keyId = requireBiometricKeyId(options?.keyId);
    return callbackPromise(
      (callback) =>
        requireBiometricModule().getSigningKey(
          JSON.stringify({ keyId }),
          callback,
        ),
      decodeSigningKey,
    );
  },

  deleteSigningKey(
    options: SigningKeyIdOptions,
  ): Promise<DeleteSigningKeyResult> {
    'background only';
    const keyId = requireBiometricKeyId(options?.keyId);
    return callbackPromise(
      (callback) =>
        requireBiometricModule().deleteSigningKey(
          JSON.stringify({ keyId }),
          callback,
        ),
      (value) => decodeDeleteResult(value, keyId),
    );
  },

  signChallenge(options: SignChallengeOptions): Promise<SignChallengeResult> {
    'background only';
    const keyId = requireBiometricKeyId(options?.keyId);
    const normalized = {
      ...promptFields(options),
      keyId,
      payload: buildBiometricSigningPayload({
        keyId,
        challenge: options.challenge,
        contextHash: options.contextHash,
      }),
    };
    return callbackPromise(
      (callback) =>
        requireBiometricModule().signChallenge(
          JSON.stringify(normalized),
          callback,
        ),
      (value) => decodeSignatureResult(value, keyId),
    );
  },
};

/** Runtime type guard useful when restoring a persisted key id. */
export const isSigningKeyId = isBiometricKeyId;
