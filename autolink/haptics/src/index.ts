import {
  completeNativeCall,
  requireNativeModule,
} from '@lynx-app/native-runtime';
import { HAPTICS_MODULE_NAME } from './native.generated.js';

export * from './native.generated.js';

export type HapticImpact = 'light' | 'medium' | 'heavy';

function normalizeHapticImpact(style: HapticImpact): HapticImpact {
  'background only';
  if (style !== 'light' && style !== 'medium' && style !== 'heavy') {
    throw new Error(`Invalid haptic impact style: ${String(style)}`);
  }
  return style;
}

function requireHapticsModule() {
  'background only';
  return requireNativeModule(HAPTICS_MODULE_NAME);
}

/** One-shot haptic feedback. */
export const haptics = {
  impact(style: HapticImpact): Promise<void> {
    'background only';
    const normalized = normalizeHapticImpact(style);
    return completeNativeCall((callback) =>
      requireHapticsModule().impact(normalized, callback),
    );
  },
};
