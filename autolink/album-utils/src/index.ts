import {
  completeNativeCall,
  decodeNativeValue,
  requireNativeModule,
} from '@lynx-app/native-runtime';
import { ALBUM_UTILS_MODULE_NAME } from './native.generated.js';

export * from './native.generated.js';

export interface PickerOptions {
  /** Maximum number of images the user may select. Defaults to 1. */
  maxSelection?: number;
}

interface PickerModule {
  pick(maxSelection: number, callback: (result: unknown) => void): void;
}

interface PickerResult {
  error?: unknown;
  uris?: unknown;
}

const MAX_PICKER_SELECTION = 50;

function normalizePickerOptions(options: PickerOptions): number {
  'background only';
  const maxSelection = options.maxSelection ?? 1;
  if (
    !Number.isInteger(maxSelection) ||
    maxSelection < 1 ||
    maxSelection > MAX_PICKER_SELECTION
  ) {
    throw new Error(
      `Picker maxSelection must be an integer from 1 to ${MAX_PICKER_SELECTION}`,
    );
  }
  return maxSelection;
}

function completePicker(
  module: PickerModule,
  maxSelection: number,
): Promise<string[]> {
  'background only';
  return new Promise((resolve, reject) => {
    module.pick(maxSelection, (result) => {
      'background only';
      try {
        const decoded = decodeNativeValue(result, 'AlbumUtils');
        if (typeof decoded !== 'object' || decoded === null) {
          throw new Error('AlbumUtils returned an invalid picker result');
        }
        const payload = decoded as PickerResult;
        if (typeof payload.error === 'string' && payload.error.length > 0) {
          reject(new Error(payload.error));
          return;
        }
        if (
          !Array.isArray(payload.uris) ||
          !payload.uris.every((uri) => typeof uri === 'string')
        ) {
          throw new Error('AlbumUtils returned an invalid URI list');
        }
        resolve(payload.uris.slice(0, maxSelection));
      } catch (error) {
        reject(error instanceof Error ? error : new Error(String(error)));
      }
    });
  });
}

function requireAlbumUtilsModule() {
  'background only';
  return requireNativeModule(ALBUM_UTILS_MODULE_NAME);
}

/** Picks images from the system album and saves image URIs back into it. */
export const albumUtils = {
  /** Selects images through the platform's user-visible album picker. */
  pick(options: PickerOptions = {}): Promise<string[]> {
    'background only';
    const maxSelection = normalizePickerOptions(options);
    return completePicker(requireAlbumUtilsModule(), maxSelection);
  },

  /**
   * Writes an image URI (a picker or cache URI readable by `fileSystem`)
   * into the system album. The platform may ask the user for confirmation.
   */
  saveToAlbum(uri: string): Promise<void> {
    'background only';
    const normalized = uri.trim();
    if (normalized.length === 0) {
      throw new Error('Image URI must not be empty');
    }
    return completeNativeCall((callback) =>
      requireAlbumUtilsModule().saveToAlbum(normalized, callback),
    );
  },
};
