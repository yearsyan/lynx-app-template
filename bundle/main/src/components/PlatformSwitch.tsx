import { useCallback } from '@lynx-js/react';

import type { GlassSwitchEvent } from './native-elements.js';

export interface PlatformSwitchProps {
  checked: boolean;
  disabled?: boolean;
  onChange: (value: boolean) => void;
}

/** iOS renders the native Liquid Glass switch; other platforms get a Lynx-built toggle. */
export function PlatformSwitch(props: PlatformSwitchProps) {
  const { checked, disabled = false, onChange } = props;

  const handleNativeChange = useCallback(
    (event: GlassSwitchEvent) => {
      'background only';
      onChange(event.detail.value);
    },
    [onChange],
  );

  const handleFallbackTap = useCallback(() => {
    'background only';
    if (!disabled) {
      onChange(!checked);
    }
  }, [checked, disabled, onChange]);

  if (SystemInfo.platform.toLowerCase() === 'ios') {
    return (
      <glass-switch
        style={{ width: '52px', height: '32px' }}
        checked={checked}
        disabled={disabled}
        bindchange={handleNativeChange}
      />
    );
  }

  return (
    <view
      className={`FallbackSwitch ${checked ? 'FallbackSwitch--on' : ''} ${
        disabled ? 'FallbackSwitch--disabled' : ''
      }`}
      bindtap={handleFallbackTap}
    >
      <view
        className={`FallbackSwitch__thumb ${
          checked ? 'FallbackSwitch__thumb--on' : ''
        }`}
      />
    </view>
  );
}
