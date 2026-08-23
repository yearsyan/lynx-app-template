import { useCallback, useEffect, useRef, useState } from '@lynx-js/react';
import type {
  LayoutChangeEvent,
  TouchEvent,
  TransitionEvent,
} from '@lynx-js/types';
import { PredictiveBackOverlay } from '@lynx-template/autolink-navigation/react';

import { t } from '../i18n.js';
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
const MENU_TRANSITION_FALLBACK_MS = 400;
// Finger travel (layout px) past which a touch on the backdrop counts as a
// scroll drag rather than a sloppy tap.
const SCROLL_DISMISS_SLOP = 10;

const isIOS = SystemInfo.platform.toLowerCase() === 'ios';

/**
 * Every platform renders the trigger and selected state with Lynx. On iOS, a
 * transparent native button above the trigger only presents the system UIMenu
 * (Liquid Glass on iOS 26); Android and HarmonyOS use the Lynx-built menu.
 */
export function PlatformDropdown(props: PlatformDropdownProps) {
  const { title, options, selected, disabled = false, onSelect } = props;
  const localizedOptions = options.map((option) => t(option));
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
  const closeTimer = useRef<number | null>(null);

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
      const index = event.detail.index;
      onSelect(index, options[index] ?? event.detail.value);
    },
    [onSelect, options],
  );

  const finishClose = useCallback(() => {
    'background only';
    if (closeTimer.current !== null) {
      clearTimeout(closeTimer.current);
      closeTimer.current = null;
    }
    setOpen(false);
  }, []);

  const close = useCallback(() => {
    'background only';
    if (!open || !expanded) {
      finishClose();
      return;
    }
    setExpanded(false);
    if (closeTimer.current !== null) {
      clearTimeout(closeTimer.current);
    }
    // Lynx emits transitionend for height on the fallback hosts. Keep a small
    // fallback so a platform interruption cannot leave the full-screen hit
    // layer mounted indefinitely.
    closeTimer.current = setTimeout(finishClose, MENU_TRANSITION_FALLBACK_MS);
  }, [expanded, finishClose, open]);

  const finishMenuTransition = useCallback(
    (event: TransitionEvent) => {
      'background only';
      const isHeightTransition =
        event.params.animation_name === 'height' ||
        event.params.animation_type === 'transition-height';
      if (isHeightTransition && open && !expanded) {
        finishClose();
      }
    },
    [expanded, finishClose, open],
  );

  const toggle = useCallback(
    (event: TouchEvent) => {
      'background only';
      if (disabled) {
        return;
      }

      if (open) {
        close();
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
    [
      close,
      disabled,
      open,
      options.length,
      triggerSize.height,
      triggerSize.width,
    ],
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

  const dismissOnScrollDrag = useCallback(
    (event: TouchEvent) => {
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
        close();
      }
    },
    [close],
  );

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
    close();
  }, [close]);

  const handleOverlayOpenChange = useCallback(
    (nextOpen: boolean) => {
      'background only';
      if (!nextOpen) {
        close();
      }
    },
    [close],
  );

  const label =
    selected >= 0 && selected < localizedOptions.length
      ? localizedOptions[selected]
      : t(title);

  return (
    <view className="FallbackDropdown">
      <view
        className={`FallbackDropdown__button ${
          disabled ? 'FallbackDropdown__button--disabled' : ''
        }`}
        bindlayoutchange={trackTriggerSize}
      >
        <text className="FallbackDropdown__label">{label}</text>
        <text className="FallbackDropdown__chevron">
          {expanded ? '▲' : '▼'}
        </text>
        {isIOS ? (
          <glass-dropdown
            className="FallbackDropdown__hitTarget"
            title={label}
            options={localizedOptions}
            selected={selected}
            disabled={disabled}
            bindselect={handleNativeSelect}
          />
        ) : (
          <view className="FallbackDropdown__hitTarget" bindtap={toggle} />
        )}
      </view>
      {!isIOS ? (
        <PredictiveBackOverlay
          open={open}
          onOpenChange={handleOverlayOpenChange}
          backdropColor="transparent"
          motion="none"
          animated={false}
          dismissOnBackdropPress={false}
          style={{ zIndex: 0 }}
          contentStyle={{ width: '100%', height: '100%' }}
        >
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
                height: expanded
                  ? `${options.length * OPTION_HEIGHT}px`
                  : '0px',
                ...(menuRect.direction === 'up'
                  ? { bottom: `${menuRect.bottom}px` }
                  : { top: `${menuRect.top}px` }),
              }}
              bindtransitionend={finishMenuTransition}
            >
              {options.map((option, index) => (
                <view
                  key={option}
                  className={`FallbackDropdown__option ${
                    index === selected
                      ? 'FallbackDropdown__option--selected'
                      : ''
                  }`}
                  bindtap={() => {
                    'background only';
                    close();
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
                    {localizedOptions[index]}
                  </text>
                </view>
              ))}
            </view>
          </view>
        </PredictiveBackOverlay>
      ) : null}
    </view>
  );
}
