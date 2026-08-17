import { NATIVE_MODULE_NAMES } from '@lynx-app/native-contracts';
import { completeNativeCall } from './completion.js';
import type { PickerModule, PickerOptions } from './fileSystem.js';
import { completePicker, normalizePickerOptions } from './fileSystem.js';
import { requireNativeModule } from './moduleRegistry.js';

function requireAlbumUtilsModule() {
  'background only';
  return requireNativeModule(NATIVE_MODULE_NAMES.AlbumUtils);
}

/** Picks images from the system album and saves image URIs back into it. */
export const albumUtils = {
  /** Selects images through the platform's user-visible album picker. */
  pick(options: PickerOptions = {}): Promise<string[]> {
    'background only';
    const maxSelection = normalizePickerOptions(options);
    return completePicker(
      requireAlbumUtilsModule() as PickerModule,
      maxSelection,
    );
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
