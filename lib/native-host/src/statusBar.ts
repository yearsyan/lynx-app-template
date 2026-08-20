import {
  completeNativeCall,
  requireStatusBarModule,
} from './bridge.generated.js';

export type StatusBarStyle = 'dark-content' | 'light-content';

export function normalizeStatusBarStyle(style: StatusBarStyle): StatusBarStyle {
  'background only';
  if (style !== 'dark-content' && style !== 'light-content') {
    throw new Error(`Invalid status bar style: ${String(style)}`);
  }
  return style;
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
