/** Domain separator prepended to every v2 server-verifiable signature. */
export const BIOMETRIC_V2_SIGNING_DOMAIN = 'LYNX_BIOMETRIC_V2' as const;

const BASE64_PATTERN =
  /^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/;
const BASE64_ALPHABET =
  'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
const SCOPE_PATTERN = /^[A-Za-z0-9._-]{1,64}$/;
const KEY_ID_PATTERN =
  /^[A-Za-z0-9._-]{1,64}~[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;

export interface BiometricSigningPayloadInput {
  keyId: string;
  /** Standard Base64 server nonce, decoded length 16..64 bytes. */
  challenge: string;
  /** Standard Base64 SHA-256 hash of the canonical business operation. */
  contextHash: string;
}

export function normalizeBiometricScope(scope: unknown): string {
  'background only';
  if (typeof scope !== 'string') {
    throw new Error('Biometric key scope must be a string');
  }
  const normalized = scope.trim();
  if (!SCOPE_PATTERN.test(normalized)) {
    throw new Error(
      'Biometric key scope must be 1..64 ASCII letters, digits, dot, underscore, or hyphen',
    );
  }
  return normalized;
}

export function isBiometricKeyId(value: unknown): value is string {
  'background only';
  return typeof value === 'string' && KEY_ID_PATTERN.test(value);
}

export function requireBiometricKeyId(value: unknown): string {
  'background only';
  if (!isBiometricKeyId(value)) {
    throw new Error('Biometric keyId is invalid');
  }
  return value;
}

export function biometricScopeFromKeyId(keyId: string): string {
  'background only';
  const normalized = requireBiometricKeyId(keyId);
  return normalized.slice(0, normalized.lastIndexOf('~'));
}

export function decodeStandardBase64(
  value: unknown,
  label: string,
): Uint8Array {
  'background only';
  if (
    typeof value !== 'string' ||
    value.length === 0 ||
    value.length % 4 !== 0 ||
    !BASE64_PATTERN.test(value)
  ) {
    throw new Error(`${label} must be non-empty standard Base64`);
  }

  const padding = value.endsWith('==') ? 2 : value.endsWith('=') ? 1 : 0;
  const output = new Uint8Array((value.length / 4) * 3 - padding);
  let outputIndex = 0;
  for (let index = 0; index < value.length; index += 4) {
    const first = BASE64_ALPHABET.indexOf(value[index] ?? '');
    const second = BASE64_ALPHABET.indexOf(value[index + 1] ?? '');
    const thirdChar = value[index + 2] ?? '=';
    const fourthChar = value[index + 3] ?? '=';
    const third = thirdChar === '=' ? 0 : BASE64_ALPHABET.indexOf(thirdChar);
    const fourth = fourthChar === '=' ? 0 : BASE64_ALPHABET.indexOf(fourthChar);
    if (first < 0 || second < 0 || third < 0 || fourth < 0) {
      throw new Error(`${label} must be non-empty standard Base64`);
    }
    const bits = (first << 18) | (second << 12) | (third << 6) | fourth;
    if (outputIndex < output.length) output[outputIndex++] = bits >> 16;
    if (outputIndex < output.length) output[outputIndex++] = bits >> 8;
    if (outputIndex < output.length) output[outputIndex++] = bits;
  }

  // Reject alternate encodings with non-zero unused padding bits.
  if (encodeStandardBase64(output) !== value) {
    throw new Error(`${label} must use canonical standard Base64`);
  }
  return output;
}

export function encodeStandardBase64(bytes: Uint8Array): string {
  'background only';
  let encoded = '';
  for (let index = 0; index < bytes.length; index += 3) {
    const first = bytes[index] ?? 0;
    const hasSecond = index + 1 < bytes.length;
    const hasThird = index + 2 < bytes.length;
    const second = bytes[index + 1] ?? 0;
    const third = bytes[index + 2] ?? 0;
    const bits = (first << 16) | (second << 8) | third;
    encoded += BASE64_ALPHABET[(bits >> 18) & 0x3f];
    encoded += BASE64_ALPHABET[(bits >> 12) & 0x3f];
    encoded += hasSecond ? BASE64_ALPHABET[(bits >> 6) & 0x3f] : '=';
    encoded += hasThird ? BASE64_ALPHABET[bits & 0x3f] : '=';
  }
  return encoded;
}

/**
 * Builds the exact bytes signed by every native v2 implementation:
 *
 *   ASCII("LYNX_BIOMETRIC_V2\0") || ASCII(keyId) || 0x00 ||
 *   contextHash[32] || challenge[16..64]
 */
export function buildBiometricSigningPayload(
  input: BiometricSigningPayloadInput,
): string {
  'background only';
  const keyId = requireBiometricKeyId(input.keyId);
  const challenge = decodeStandardBase64(
    input.challenge.trim(),
    'Biometric challenge',
  );
  if (challenge.length < 16 || challenge.length > 64) {
    throw new Error('Biometric challenge must decode to 16..64 bytes');
  }
  const contextHash = decodeStandardBase64(
    input.contextHash.trim(),
    'Biometric contextHash',
  );
  if (contextHash.length !== 32) {
    throw new Error('Biometric contextHash must be a 32-byte SHA-256 hash');
  }

  const domain = asciiBytes(`${BIOMETRIC_V2_SIGNING_DOMAIN}\0`);
  const key = asciiBytes(keyId);
  const payload = new Uint8Array(
    domain.length + key.length + 1 + contextHash.length + challenge.length,
  );
  let offset = 0;
  payload.set(domain, offset);
  offset += domain.length;
  payload.set(key, offset);
  offset += key.length;
  payload[offset++] = 0;
  payload.set(contextHash, offset);
  offset += contextHash.length;
  payload.set(challenge, offset);
  return encodeStandardBase64(payload);
}

function asciiBytes(value: string): Uint8Array {
  'background only';
  const bytes = new Uint8Array(value.length);
  for (let index = 0; index < value.length; index += 1) {
    const code = value.charCodeAt(index);
    if (code > 0x7f) throw new Error('Biometric protocol values must be ASCII');
    bytes[index] = code;
  }
  return bytes;
}
