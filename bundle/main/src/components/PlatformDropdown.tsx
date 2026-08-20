import { useCallback, useEffect, useRef, useState } from '@lynx-js/react';
import type { LayoutChangeEvent, TouchEvent } from '@lynx-js/types';
import { useBackInterceptor } from '@lynx-template/autolink-back/react';

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
  right: number;
  top: number;
  bottom: number;
  width: number;
  height: number;
}

interface MenuRect {
  bottom: number;
  direction: 'down' | 'up';
  left: number;
  top: number;
  width: number;
}

interface TriggerSize {
  width: number;
  height: number;
}

const DROPDOWN_GAP = 6;
const MENU_EDGE_INSET = 8;
const OPTION_HEIGHT = 42;
// Finger travel (layout px) past which a touch on the backdrop counts as a
// scroll drag rather than a sloppy tap.
const SCROLL_DISMISS_SLOP = 10;

const isIOS = SystemInfo.platform.toLowerCase() === 'ios';

/**
 * iOS renders the native Liquid Glass menu button; other platforms get a
 * Lynx-built dropdown whose menu floats above the page via `position: fixed`
 * (recommended over <overlay> for fully Lynx-rendered pages) and closes on
 * backdrop tap, a scroll drag behind it, or the system back button
 * (back interception).
 */
export function PlatformDropdown(props: PlatformDropdownProps) {
  const { title, options, selected, disabled = false, onSelect } = props;
  const [open, setOpen] = useState(false);
  const [expanded, setExpanded] = useState(false);
  const [triggerSize, setTriggerSize] = useState<TriggerSize>({
    width: 0,
    height: 0,
  });
  const [menuRect, setMenuRect] = useState<MenuRect>({
    bottom: 0,
    direction: 'down',
    left: 0,
    top: 0,
    width: 0,
  });
  const gestureStart = useRef<{ x: number; y: number } | null>(null);

  // Enabled only while open, so this menu sits on top of every popup that
  // was opened before it; disabling reveals the previous interceptor.
  useBackInterceptor((event) => {
    'background only';
    if (event.phase === 'commit') {
      setOpen(false);
    }
  }, !isIOS && open);

  useEffect(() => {
    if (isIOS) {
      return;
    }
    if (!open) {
      setExpanded(false);
      return;
    }
    const frame = requestAnimationFrame(() => setExpanded(true));
    return () => cancelAnimationFrame(frame);
  }, [open]);

  const handleNativeSelect = useCallback(
    (event: GlassDropdownEvent) => {
      'background only';
      onSelect(event.detail.index, event.detail.value);
    },
    [onSelect],
  );

  const toggle = useCallback(
    (event: TouchEvent) => {
      'background only';
      if (disabled) {
        return;
      }

      if (open) {
        setOpen(false);
        return;
      }

      const touch = event.changedTouches[0] ?? event.touches[0];
      if (touch === undefined || triggerSize.width <= 0) {
        return;
      }

      const pixelRatio = SystemInfo.pixelRatio;
      const viewportWidth = SystemInfo.pixelWidth / pixelRatio;
      const viewportHeight = SystemInfo.pixelHeight / pixelRatio;
      // Touch and layout coordinates already use Lynx layout px. Only the
      // physical SystemInfo viewport dimensions need pixel-ratio conversion.
      const anchorLeft = touch.clientX - touch.x;
      const anchorTop = touch.clientY - touch.y;
      const anchor: AnchorRect = {
        left: anchorLeft,
        right: anchorLeft + triggerSize.width,
        top: anchorTop,
        bottom: anchorTop + triggerSize.height,
        width: triggerSize.width,
        height: triggerSize.height,
      };
      const viewport: AnchorRect = {
        left: 0,
        right: viewportWidth,
        top: 0,
        bottom: viewportHeight,
        width: viewportWidth,
        height: viewportHeight,
      };
      const menuHeight = options.length * OPTION_HEIGHT;
      const spaceBelow =
        viewport.bottom - MENU_EDGE_INSET - anchor.bottom - DROPDOWN_GAP;
      const spaceAbove =
        anchor.top - DROPDOWN_GAP - viewport.top - MENU_EDGE_INSET;
      const openBelow = spaceBelow >= menuHeight || spaceBelow >= spaceAbove;
      const requestedTop = openBelow
        ? anchor.bottom + DROPDOWN_GAP
        : anchor.top - DROPDOWN_GAP - menuHeight;
      const minTop = viewport.top + MENU_EDGE_INSET;
      const maxTop = Math.max(
        minTop,
        viewport.bottom - MENU_EDGE_INSET - menuHeight,
      );
      const maxLeft = Math.max(
        viewport.left + MENU_EDGE_INSET,
        viewport.right - MENU_EDGE_INSET - anchor.width,
      );
      const top = Math.min(Math.max(requestedTop, minTop), maxTop);

      setMenuRect({
        bottom: viewport.bottom - top - menuHeight,
        direction: openBelow ? 'down' : 'up',
        left: Math.min(
          Math.max(anchor.left, viewport.left + MENU_EDGE_INSET),
          maxLeft,
        ),
        top,
        width: anchor.width,
      });
      setOpen(true);
    },
    [disabled, open, options.length, triggerSize.height, triggerSize.width],
  );

  const trackTriggerSize = useCallback((event: LayoutChangeEvent) => {
    'background only';
    const { width, height } = event.detail;
    setTriggerSize((current) =>
      current.width === width && current.height === height
        ? current
        : { width, height },
    );
  }, []);

  const close = useCallback(() => {
    'background only';
    setOpen(false);
  }, []);

  // While open, the fixed backdrop is hit-tested before the page, so every
  // scroll gesture starts on it. The menu is anchored to viewport
  // coordinates and cannot follow the scrolling content, so once the finger
  // travels past the tap slop the gesture belongs to the underlying
  // scroll-view: dismiss the menu and let the scroll continue. The slop
  // keeps a slightly shaky tap on a menu option from being misread.
  const trackGestureStart = useCallback((event: TouchEvent) => {
    'background only';
    const touch = event.changedTouches[0] ?? event.touches[0];
    gestureStart.current =
      touch === undefined ? null : { x: touch.clientX, y: touch.clientY };
  }, []);

  const dismissOnScrollDrag = useCallback((event: TouchEvent) => {
    'background only';
    const start = gestureStart.current;
    const touch = event.changedTouches[0] ?? event.touches[0];
    if (start === null || touch === undefined) {
      return;
    }
    const deltaX = touch.clientX - start.x;
    const deltaY = touch.clientY - start.y;
    if (deltaX * deltaX + deltaY * deltaY > SCROLL_DISMISS_SLOP ** 2) {
      gestureStart.current = null;
      setOpen(false);
    }
  }, []);

  const endGestureTracking = useCallback(() => {
    'background only';
    gestureStart.current = null;
  }, []);

  // Some platforms cancel the backdrop's touch stream as soon as the
  // scroll-view takes over the gesture, without delivering any touchmove.
  // That tap can no longer land anywhere useful, so close instead of
  // leaving the menu stuck above moving content.
  const interruptGesture = useCallback(() => {
    'background only';
    gestureStart.current = null;
    setOpen(false);
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
        bindlayoutchange={trackTriggerSize}
      >
        <text className="FallbackDropdown__label">{label}</text>
        <text className="FallbackDropdown__chevron">{open ? '▲' : '▼'}</text>
        <view className="FallbackDropdown__hitTarget" bindtap={toggle} />
      </view>
      {open ? (
        <view
          className="FallbackDropdown__backdrop"
          bindtap={close}
          bindtouchstart={trackGestureStart}
          bindtouchmove={dismissOnScrollDrag}
          bindtouchend={endGestureTracking}
          bindtouchcancel={interruptGesture}
        >
          <view
            className="FallbackDropdown__menu"
            style={{
              position: 'absolute',
              left: `${menuRect.left}px`,
              width: `${menuRect.width}px`,
              height: expanded ? `${options.length * OPTION_HEIGHT}px` : '0px',
              ...(menuRect.direction === 'up'
                ? { bottom: `${menuRect.bottom}px` }
                : { top: `${menuRect.top}px` }),
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
