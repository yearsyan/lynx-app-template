import type { ReactNode } from '@lynx-js/react';
import type { StandardProps } from '@lynx-js/types';

export const PRESSABLE_VIEW_ELEMENT_NAME = 'pressable-view';

/** Event emitted once after native gesture arbitration accepts a tap. */
export interface PressableViewPressEvent {
  type: 'press';
  detail: Record<string, never>;
}

export interface PressableViewProps extends StandardProps {
  children?: ReactNode;
  /** Opacity multiplier while pressed. Values are clamped to [0, 1]. */
  'active-opacity'?: number;
  /** Native foreground state-layer color shown while pressed. */
  'pressed-overlay-color'?: string;
  /** Disables visual feedback, activation, and accessibility actions. */
  disabled?: boolean;
  /** Fires only for a completed native press, never for a scroll gesture. */
  bindpress?: (event: PressableViewPressEvent) => void;
}

// IntrinsicElements is augmented by each consumer so the declaration merges
// into that consumer's catalog-pinned @lynx-js/types instance.
