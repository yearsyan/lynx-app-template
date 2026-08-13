import { useCallback, useEffect, useState } from '@lynx-js/react';
import type { LayoutChangeEvent } from '@lynx-js/types';
import { nativeBack } from '@lynx-template/native-bridge';

import type { GlassDropdownEvent } from './native-elements.js';

export interface PlatformDropdownProps {
  title: string;
  options: string[];
  selected: number;
  disabled?: boolean;
  onSelect: (index: number, value: string) => void;
}

interface AnchorRect {
  left: number;
  top: number;
  width: number;
  height: number;
}

const isIOS = SystemInfo.platform.toLowerCase() === 'ios';

/**
 * iOS renders the native Liquid Glass menu button; other platforms get a
 * Lynx-built dropdown whose menu floats above the page via `position: fixed`
 * (recommended over <overlay> for fully Lynx-rendered pages) and closes on
 * backdrop tap or the system back button (nativeBack interception).
 */
export function PlatformDropdown(props: PlatformDropdownProps) {
  const { title, options, selected, disabled = false, onSelect } = props;
  const [open, setOpen] = useState(false);
  const [anchor, setAnchor] = useState<AnchorRect>({
    left: 0,
    top: 0,
    width: 0,
    height: 0,
  });

  // While the fallback menu is open, intercept the system back button/gesture
  // so it closes the menu instead of leaving the page.
  useEffect(() => {
    if (isIOS || !open) {
      return;
    }
    nativeBack.setEnabled(true).catch(() => {});
    return () => {
      nativeBack.setEnabled(false).catch(() => {});
    };
  }, [open]);

  useEffect(() => {
    if (isIOS) {
      return;
    }
    return nativeBack.addListener((event) => {
      'background only';
      if (event.phase === 'commit') {
        setOpen(false);
      }
    });
  }, []);

  const handleNativeSelect = useCallback(
    (event: GlassDropdownEvent) => {
      'background only';
      onSelect(event.detail.index, event.detail.value);
    },
    [onSelect],
  );

  const toggle = useCallback(() => {
    'background only';
    if (!disabled) {
      setOpen((current) => !current);
    }
  }, [disabled]);

  const close = useCallback(() => {
    'background only';
    setOpen(false);
  }, []);

  const trackAnchor = useCallback((event: LayoutChangeEvent) => {
    'background only';
    const { left, top, width, height } = event.detail;
    setAnchor((current) =>
      current.left === left &&
      current.top === top &&
      current.width === width &&
      current.height === height
        ? current
        : { left, top, width, height },
    );
  }, []);

  const label =
    selected >= 0 && selected < options.length ? options[selected] : title;

  if (isIOS) {
    return (
      <glass-dropdown
        style={{ width: '100%', height: '44px' }}
        title={title}
        options={options}
        selected={selected}
        disabled={disabled}
        bindselect={handleNativeSelect}
      />
    );
  }

  return (
    <view className="FallbackDropdown">
      <view
        className={`FallbackDropdown__button ${
          disabled ? 'FallbackDropdown__button--disabled' : ''
        }`}
        bindtap={toggle}
        bindlayoutchange={trackAnchor}
      >
        <text className="FallbackDropdown__label">{label}</text>
        <text className="FallbackDropdown__chevron">{open ? '▲' : '▼'}</text>
      </view>
      {open ? (
        <view className="FallbackDropdown__backdrop" bindtap={close}>
          <view
            className="FallbackDropdown__menu"
            style={{
              position: 'absolute',
              left: `${anchor.left}px`,
              top: `${anchor.top + anchor.height + 6}px`,
              width: `${anchor.width}px`,
            }}
          >
            {options.map((option, index) => (
              <view
                key={option}
                className={`FallbackDropdown__option ${
                  index === selected ? 'FallbackDropdown__option--selected' : ''
                }`}
                bindtap={() => {
                  'background only';
                  setOpen(false);
                  onSelect(index, option);
                }}
              >
                <text
                  className={`FallbackDropdown__optionLabel ${
                    index === selected
                      ? 'FallbackDropdown__optionLabel--selected'
                      : ''
                  }`}
                >
                  {option}
                </text>
              </view>
            ))}
          </view>
        </view>
      ) : null}
    </view>
  );
}
