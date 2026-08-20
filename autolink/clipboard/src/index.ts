import { completeNativeCall, requireNativeModule } from './bridge.generated.js';

export * from './native.generated.js';

function requireClipboardModule() {
  'background only';
  return requireNativeModule();
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
