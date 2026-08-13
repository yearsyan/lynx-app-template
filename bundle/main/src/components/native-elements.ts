import type { StandardProps } from '@lynx-js/types';

/** Event detail emitted by the native `glass-switch` element (iOS only). */
export interface GlassSwitchChangeDetail {
  value: boolean;
}

/** Event detail emitted by the native `glass-dropdown` element (iOS only). */
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

declare module '@lynx-js/types' {
  interface IntrinsicElements {
    'glass-switch': GlassSwitchProps;
    'glass-dropdown': GlassDropdownProps;
  }
}
