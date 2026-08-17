import { NATIVE_MODULE_NAMES } from '@lynx-app/native-contracts';
import { completeNativeCall } from './completion.js';
import { requireNativeModule } from './moduleRegistry.js';

function requireClipboardModule() {
  'background only';
  return requireNativeModule(NATIVE_MODULE_NAMES.Clipboard);
}

/** System clipboard for plain text. */
export const clipboard = {
  setString(text: string): Promise<void> {
    'background only';
    return completeNativeCall((callback) =>
      requireClipboardModule().setString(text, callback),
    );
  },

  getString(): Promise<string | null> {
    'background only';
    return new Promise((resolve) => {
      requireClipboardModule().getString((text) => {
        'background only';
        resolve(typeof text === 'string' ? text : null);
      });
    });
  },
};
