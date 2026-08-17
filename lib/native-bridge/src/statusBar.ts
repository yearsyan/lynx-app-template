import { NATIVE_MODULE_NAMES } from '@lynx-app/native-contracts';
import { completeNativeCall } from './completion.js';
import { requireNativeModule } from './moduleRegistry.js';

export type StatusBarStyle = 'dark-content' | 'light-content';

export function normalizeStatusBarStyle(style: StatusBarStyle): StatusBarStyle {
  'background only';
  if (style !== 'dark-content' && style !== 'light-content') {
    throw new Error(`Invalid status bar style: ${String(style)}`);
  }
  return style;
}

function requireStatusBarModule() {
  'background only';
  return requireNativeModule(NATIVE_MODULE_NAMES.StatusBar);
}

/** Controls the foreground color of the current native status bar. */
export const statusBar = {
  setStyle(style: StatusBarStyle): Promise<void> {
    'background only';
    const normalized = normalizeStatusBarStyle(style);
    return completeNativeCall((callback) =>
      requireStatusBarModule().setStyle(normalized, callback),
    );
  },
};
