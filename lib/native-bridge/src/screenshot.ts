import {
  NATIVE_MODULE_NAMES,
  type ScreenshotModule,
} from '@lynx-app/native-contracts';
import { requireNativeModule } from './moduleRegistry.js';

export type ScreenshotFormat = 'png' | 'jpeg';

export interface ScreenshotOptions {
  /**
   * `idSelector` of a Lynx element to capture instead of the whole LynxView.
   * Not supported on HarmonyOS, where only the whole view area can be
   * captured — the host rejects the call instead of silently ignoring it.
   */
  idSelector?: string;
  /** Encoded image format. Defaults to `'png'`. */
  format?: ScreenshotFormat;
  /** JPEG quality from 1 to 100. Ignored for PNG. Defaults to 80. */
  quality?: number;
  /** Base file name inside the cache directory. */
  fileName?: string;
}

export interface ScreenshotResult {
  /** `file://` URI of the encoded image inside the app cache directory. */
  uri: string;
  /** Encoded image width in pixels. */
  width: number;
  /** Encoded image height in pixels. */
  height: number;
}

/** Normalized request handed to the platform modules. */
export interface ScreenshotRequest {
  idSelector: string | null;
  format: ScreenshotFormat;
  quality: number;
  fileName: string | null;
}

interface ScreenshotValueResult {
  error?: unknown;
  value?: unknown;
}

const DEFAULT_JPEG_QUALITY = 80;
const MAX_FILE_NAME_LENGTH = 120;

function requireScreenshotModule(): ScreenshotModule {
  'background only';
  return requireNativeModule(NATIVE_MODULE_NAMES.Screenshot);
}

function normalizeRequest(
  options: ScreenshotOptions,
  allowIdSelector: boolean,
): ScreenshotRequest {
  'background only';
  let idSelector: string | null = null;
  if (options.idSelector !== undefined) {
    const normalized = options.idSelector.trim();
    if (normalized.length > 0) {
      if (!allowIdSelector) {
        throw new Error('Screenshot capturePage does not support idSelector');
      }
      if (normalized.length > 128) {
        throw new Error('Screenshot idSelector is longer than 128 characters');
      }
      idSelector = normalized;
    }
  }

  const format = options.format ?? 'png';
  if (format !== 'png' && format !== 'jpeg') {
    throw new Error(`Invalid screenshot format: ${String(format)}`);
  }

  const quality = options.quality ?? DEFAULT_JPEG_QUALITY;
  if (!Number.isInteger(quality) || quality < 1 || quality > 100) {
    throw new Error('Screenshot quality must be an integer from 1 to 100');
  }

  let fileName: string | null = null;
  if (options.fileName !== undefined) {
    const normalized = options.fileName.trim();
    if (normalized.length > 0) {
      if (normalized.length > MAX_FILE_NAME_LENGTH) {
        throw new Error(
          `Screenshot fileName is longer than ${MAX_FILE_NAME_LENGTH} characters`,
        );
      }
      const invalidCharacter = Array.from(normalized).some((char) => {
        const code = char.charCodeAt(0);
        return char === '/' || char === '\\' || (code >= 0 && code <= 0x1f);
      });
      if (invalidCharacter) {
        throw new Error(
          'Screenshot fileName must not contain separators or control characters',
        );
      }
      fileName = normalized;
    }
  }

  return { idSelector, format, quality, fileName };
}

function decodeResult(value: unknown): ScreenshotResult {
  if (typeof value !== 'object' || value === null) {
    throw new Error('Screenshot returned an invalid result');
  }
  const result = value as Partial<ScreenshotResult>;
  if (
    typeof result.uri !== 'string' ||
    result.uri.length === 0 ||
    typeof result.width !== 'number' ||
    !Number.isSafeInteger(result.width) ||
    result.width < 1 ||
    typeof result.height !== 'number' ||
    !Number.isSafeInteger(result.height) ||
    result.height < 1
  ) {
    throw new Error('Screenshot returned an invalid result');
  }
  return result as ScreenshotResult;
}

function invokeScreenshot(
  action: (callback: (resultJSON: string) => void) => void,
): Promise<ScreenshotResult> {
  'background only';
  return new Promise((resolve, reject) => {
    try {
      action((resultJSON) => {
        'background only';
        try {
          if (typeof resultJSON !== 'string') {
            throw new Error('Screenshot returned a non-string result');
          }
          const parsed = JSON.parse(resultJSON) as unknown;
          if (typeof parsed !== 'object' || parsed === null) {
            throw new Error('Screenshot returned an invalid result');
          }
          const result = parsed as ScreenshotValueResult;
          if (typeof result.error === 'string' && result.error.length > 0) {
            reject(new Error(result.error));
            return;
          }
          resolve(decodeResult(result.value));
        } catch (error) {
          reject(error instanceof Error ? error : new Error(String(error)));
        }
      });
    } catch (error) {
      reject(error instanceof Error ? error : new Error(String(error)));
    }
  });
}

/** View snapshots encoded into the app cache directory. */
export const screenshot = {
  /**
   * Captures the whole LynxView, or the element matching `options.idSelector`
   * when provided, and saves it as PNG/JPEG inside the app cache directory.
   */
  capture(options: ScreenshotOptions = {}): Promise<ScreenshotResult> {
    'background only';
    const request = normalizeRequest(options, true);
    return invokeScreenshot((callback) =>
      requireScreenshotModule().capture(request, callback),
    );
  },

  /**
   * Captures the current native page exactly as composed on screen — the
   * equivalent of Android's window PixelCopy — without any screenshot
   * permission. Saves PNG/JPEG into the app cache directory.
   */
  capturePage(options: ScreenshotOptions = {}): Promise<ScreenshotResult> {
    'background only';
    const request = normalizeRequest(options, false);
    return invokeScreenshot((callback) =>
      requireScreenshotModule().capturePage(request, callback),
    );
  },
};
