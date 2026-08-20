/**
 * QR and barcode scanning provided by the native Scanner module: a
 * full-screen camera scan page and still-image decoding.
 */
import {
  decodeNativeEnvelope,
  requireNativeModule,
} from './bridge.generated.js';

export * from './native.generated.js';

/**
 * Normalized code symbology shared by the three hosts. HarmonyOS can also
 * report its system-specific `multifunctional` code; iOS reports UPC-A as
 * `ean_13` because AVFoundation exposes it that way.
 */
export type ScanFormat =
  | 'qr_code'
  | 'aztec'
  | 'codabar'
  | 'code39'
  | 'code93'
  | 'code128'
  | 'data_matrix'
  | 'ean_8'
  | 'ean_13'
  | 'itf'
  | 'pdf417'
  | 'upc_a'
  | 'upc_e'
  | 'multifunctional'
  | 'unknown';

/**
 * Terminal state of one scan request. Codes reachable through normal user
 * flow ('userCancel', 'permissionDenied', 'noCodeFound', …) resolve instead
 * of rejecting so business logic can branch without try/catch.
 */
export type ScanOutcomeCode =
  | 'success'
  | 'userCancel'
  | 'permissionDenied'
  | 'unavailable'
  | 'busy'
  /** `scanFromImage` only: the image contained no readable code. */
  | 'noCodeFound';

export interface ScanOutcome {
  /** Convenience flag, always `code === 'success'`. */
  readonly success: boolean;
  readonly code: ScanOutcomeCode;
  /**
   * Decoded code payload when successful; `null` for every other outcome.
   * Treat it as an untrusted string: never `eval` it and confirm URLs with
   * the user or the server before acting on them.
   */
  readonly content: string | null;
  /** Symbology of the decoded code; `null` unless `code === 'success'`. */
  readonly format: ScanFormat | null;
  /** Native diagnostic; intended for logging, not for user display. */
  readonly message: string;
}

const SCAN_FORMATS: readonly string[] = [
  'qr_code',
  'aztec',
  'codabar',
  'code39',
  'code93',
  'code128',
  'data_matrix',
  'ean_8',
  'ean_13',
  'itf',
  'pdf417',
  'upc_a',
  'upc_e',
  'multifunctional',
  'unknown',
];

const SCAN_OUTCOME_CODES: readonly string[] = [
  'success',
  'userCancel',
  'permissionDenied',
  'unavailable',
  'busy',
  'noCodeFound',
];

interface ScannerEnvelope {
  error?: unknown;
  value?: unknown;
}

function requireScannerModule() {
  'background only';
  return requireNativeModule();
}

function decodeEnvelope(result: unknown): ScannerEnvelope {
  'background only';
  return decodeNativeEnvelope(result, 'Scanner') as ScannerEnvelope;
}

function decodeOutcome(value: unknown): ScanOutcome {
  'background only';
  if (typeof value !== 'object' || value === null) {
    throw new Error('Scanner returned an invalid outcome');
  }
  const outcome = value as Partial<ScanOutcome>;
  if (
    typeof outcome.code !== 'string' ||
    !SCAN_OUTCOME_CODES.includes(outcome.code)
  ) {
    throw new Error('Scanner returned an invalid outcome code');
  }
  const success = outcome.code === 'success';
  const content =
    success && typeof outcome.content === 'string' ? outcome.content : null;
  const format =
    success &&
    typeof outcome.format === 'string' &&
    SCAN_FORMATS.includes(outcome.format)
      ? (outcome.format as ScanFormat)
      : null;
  if (success && content === null) {
    throw new Error('Scanner returned no content for a successful scan');
  }
  if (success && format === null) {
    throw new Error('Scanner returned an invalid scan format');
  }
  return {
    success,
    code: outcome.code,
    content,
    format,
    message: typeof outcome.message === 'string' ? outcome.message : '',
  };
}

function invokeScanner(
  action: (callback: (result: unknown) => void) => void,
): Promise<ScanOutcome> {
  'background only';
  return new Promise((resolve, reject) => {
    try {
      action((result) => {
        'background only';
        try {
          const envelope = decodeEnvelope(result);
          if (typeof envelope.error === 'string' && envelope.error.length > 0) {
            reject(new Error(envelope.error));
            return;
          }
          resolve(decodeOutcome(envelope.value));
        } catch (error) {
          reject(error instanceof Error ? error : new Error(String(error)));
        }
      });
    } catch (error) {
      reject(error instanceof Error ? error : new Error(String(error)));
    }
  });
}

/** Camera scanning and still-image code decoding. */
export const scanner = {
  /**
   * Opens the platform's full-screen code scanner and resolves with the
   * first code found. The user cancelling the page, denying the camera
   * permission (Android / iOS) and other user-visible branches resolve as
   * outcome codes; only invalid calls and host errors reject.
   */
  scan(): Promise<ScanOutcome> {
    'background only';
    return invokeScanner((callback) => requireScannerModule().scan(callback));
  },

  /**
   * Decodes a QR/barcode from a local image URI — for example an
   * `albumUtils.pick()` result — without touching the camera, so it needs
   * no permission on any platform. Resolves `noCodeFound` when the image
   * contains no readable code.
   */
  scanFromImage(uri: string): Promise<ScanOutcome> {
    'background only';
    const normalized = uri.trim();
    if (normalized.length === 0) {
      throw new Error('Image URI must not be empty');
    }
    return invokeScanner((callback) =>
      requireScannerModule().scanFromImage(normalized, callback),
    );
  },
};
