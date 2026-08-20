/**
 * Compatibility re-export for the main bundle. The Autolink library owns both
 * the native elements and their JSX/event contract.
 *
 * The IntrinsicElements augmentation lives in the consumer rather than in
 * autolink/liquid-glass: `declare module '@lynx-js/types'` merges into the
 * @lynx-js/types instance resolved from the file that declares it, and the
 * library's peer range can resolve to a different copy than the bundle's
 * catalog-pinned one in freshly installed projects.
 */
import type {
  GlassDropdownProps,
  GlassSwitchProps,
} from '@lynx-template/autolink-liquid-glass';
import type { PressableViewProps } from '@lynx-template/autolink-pressable-view';

declare module '@lynx-js/types' {
  interface IntrinsicElements {
    'glass-switch': GlassSwitchProps;
    'glass-dropdown': GlassDropdownProps;
    'pressable-view': PressableViewProps;
  }
}

export type {
  GlassDropdownEvent,
  GlassDropdownProps,
  GlassDropdownSelectDetail,
  GlassSwitchChangeDetail,
  GlassSwitchEvent,
  GlassSwitchProps,
} from '@lynx-template/autolink-liquid-glass';
export type {
  PressableViewPressEvent,
  PressableViewProps,
} from '@lynx-template/autolink-pressable-view';
