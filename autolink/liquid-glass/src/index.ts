import type { StandardProps } from '@lynx-js/types';

export const GLASS_SWITCH_ELEMENT_NAME = 'glass-switch';
export const GLASS_DROPDOWN_ELEMENT_NAME = 'glass-dropdown';

/** Event detail emitted by the native `glass-switch` element. */
export interface GlassSwitchChangeDetail {
  value: boolean;
}

/** Event detail emitted by the native `glass-dropdown` element. */
export interface GlassDropdownSelectDetail {
  index: number;
  value: string;
}

export interface GlassSwitchEvent {
  type: string;
  detail: GlassSwitchChangeDetail;
}

export interface GlassDropdownEvent {
  type: string;
  detail: GlassDropdownSelectDetail;
}

export interface GlassSwitchProps extends StandardProps {
  checked?: boolean;
  disabled?: boolean;
  bindchange?: (event: GlassSwitchEvent) => void;
}

export interface GlassDropdownProps extends StandardProps {
  title?: string;
  options?: string[];
  selected?: number;
  disabled?: boolean;
  bindselect?: (event: GlassDropdownEvent) => void;
}

// No IntrinsicElements augmentation here on purpose: module augmentations
// merge into the @lynx-js/types copy resolved from this file, and this
// package's peer range can resolve to a different copy than the consuming
// bundle's catalog-pinned one. Consumers augment '@lynx-js/types' themselves
// (see bundle/main/src/components/native-elements.ts).
