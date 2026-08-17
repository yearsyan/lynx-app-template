import { NATIVE_MODULE_NAMES } from '@lynx-app/native-contracts';
import { completeNativeCall } from './completion.js';
import { requireNativeModule } from './moduleRegistry.js';

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
  return requireNativeModule(NATIVE_MODULE_NAMES.Haptics);
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
