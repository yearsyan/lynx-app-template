import {
  type Dispatch,
  type ReactNode,
  type SetStateAction,
  useCallback,
  useEffect,
  useRef,
  useState,
} from '@lynx-js/react';
import type {
  CSSProperties,
  LayoutChangeEvent,
  StandardProps,
} from '@lynx-js/types';

import { type BackEvent, type BackListener, backStack } from './index.js';

export const PREDICTIVE_BACK_OVERLAY_ELEMENT_NAME =
  'predictive-back-overlay' as const;

export type PredictiveBackOverlayMotion = 'sheet' | 'horizontal' | 'none';
export type PredictiveBackOverlayDismissReason = 'back' | 'backdrop' | 'drag';

interface PredictiveBackOverlayTransitionEvent {
  detail?: {
    presented?: boolean;
  };
}

export interface PredictiveBackOverlayElementProps extends StandardProps {
  children?: ReactNode;
  'target-id': string;
  'backdrop-color'?: string;
  motion?: PredictiveBackOverlayMotion;
  presented?: boolean;
  'animate-presence'?: boolean;
  'drag-to-dismiss'?: boolean;
  'drag-dismiss-threshold'?: number;
  'content-height-ratio'?: number;
  bindoverlaytransitionend?: (
    event: PredictiveBackOverlayTransitionEvent,
  ) => void;
  binddragdismiss?: () => void;
  bindbackdroppress?: () => void;
}

declare module '@lynx-js/types' {
  interface IntrinsicElements {
    'predictive-back-overlay': PredictiveBackOverlayElementProps;
  }
}

export interface PredictiveBackOverlayController {
  readonly open: boolean;
  readonly setOpen: Dispatch<SetStateAction<boolean>>;
  present(): void;
  dismiss(): void;
  toggle(): void;
}

/** Owns the visible value and the small imperative surface an overlay needs. */
export function usePredictiveBackOverlay(
  initiallyOpen = false,
): PredictiveBackOverlayController {
  const [open, setOpen] = useState(initiallyOpen);
  const present = useCallback(() => {
    'background only';
    setOpen(true);
  }, []);
  const dismiss = useCallback(() => {
    'background only';
    setOpen(false);
  }, []);
  const toggle = useCallback(() => {
    'background only';
    setOpen((current) => !current);
  }, []);
  return { open, setOpen, present, dismiss, toggle };
}

export interface PredictiveBackOverlayProps {
  open: boolean;
  onOpenChange: (
    open: boolean,
    reason: PredictiveBackOverlayDismissReason,
  ) => void;
  children?: ReactNode;
  /** Native backdrop color; its opacity follows predictive Back progress. */
  backdropColor?: string;
  /** Native motion preset. Per-frame JavaScript callbacks are intentionally avoided. */
  motion?: PredictiveBackOverlayMotion;
  /** Animates mounting and controlled close transitions before unmounting. */
  animated?: boolean;
  /** Lets a sheet follow a downward drag and either dismiss or spring back. */
  dragToDismiss?: boolean;
  /** Fraction of the sheet height that commits a drag dismissal. */
  dragDismissThreshold?: number;
  dismissOnBackdropPress?: boolean;
  onBackEvent?: BackListener;
  onEntered?: () => void;
  onExited?: () => void;
  className?: string;
  style?: CSSProperties;
  contentClassName?: string;
  contentStyle?: CSSProperties;
}

const ROOT_STYLE: CSSProperties = {
  position: 'fixed',
  top: 0,
  right: 0,
  bottom: 0,
  left: 0,
  display: 'flex',
  flexDirection: 'column',
  justifyContent: 'flex-end',
};

// The child fills the overlay and bottom-anchors the sheet itself. Besides
// mirroring the root style, a full-screen child makes the engine's native
// hit rect cover the whole overlay on HarmonyOS, where children of a
// custom-layout UI keep their unaligned origin and would otherwise only
// react to taps along a top strip.
const CHILD_WRAPPER_STYLE: CSSProperties = {
  width: '100%',
  height: '100%',
  display: 'flex',
  flexDirection: 'column',
  justifyContent: 'flex-end',
};

const CONTENT_STYLE: CSSProperties = {
  width: '100%',
};

let nextPredictiveBackOverlayId = 0;

/**
 * Fixed overlay whose top-of-stack Back gesture is rendered directly by the
 * Android/iOS native element. HarmonyOS receives the same discrete commit API.
 */
export function PredictiveBackOverlay(
  props: PredictiveBackOverlayProps,
): ReactNode {
  const {
    open,
    onOpenChange,
    children,
    backdropColor = 'rgba(0, 0, 0, 0.45)',
    motion = 'sheet',
    animated = true,
    dragToDismiss = false,
    dragDismissThreshold = 0.22,
    dismissOnBackdropPress = true,
    onBackEvent,
    onEntered,
    onExited,
    className,
    style,
    contentClassName,
    contentStyle,
  } = props;
  const [targetId] = useState(
    () => `predictive-back-overlay-${++nextPredictiveBackOverlayId}`,
  );
  const [mounted, setMounted] = useState(open);
  const [layout, setLayout] = useState({ contentHeight: 0, rootHeight: 0 });
  const onOpenChangeRef = useRef(onOpenChange);
  const onBackEventRef = useRef(onBackEvent);
  const onEnteredRef = useRef(onEntered);
  const onExitedRef = useRef(onExited);
  const openRef = useRef(open);
  const rendered = open || mounted;

  useEffect(() => {
    onOpenChangeRef.current = onOpenChange;
    onBackEventRef.current = onBackEvent;
    onEnteredRef.current = onEntered;
    onExitedRef.current = onExited;
    openRef.current = open;
  });

  useEffect(() => {
    if (open) {
      setMounted(true);
    }
  }, [open]);

  useEffect(() => {
    if (!rendered) {
      return;
    }
    const registration = backStack.addInterceptor(
      (event: BackEvent) => {
        'background only';
        onBackEventRef.current?.(event);
        if (event.phase === 'commit' && openRef.current) {
          onOpenChangeRef.current(false, 'back');
        }
      },
      // While the top layer is leaving it still consumes Back, but must not
      // be snapped back to its presented position by a second gesture.
      { animationTargetId: open ? targetId : undefined },
    );
    return registration.remove;
  }, [open, rendered, targetId]);

  const dismissFromBackdrop = useCallback(() => {
    'background only';
    if (dismissOnBackdropPress && openRef.current) {
      onOpenChangeRef.current(false, 'backdrop');
    }
  }, [dismissOnBackdropPress]);

  const handleTransitionEnd = useCallback(
    (event: PredictiveBackOverlayTransitionEvent) => {
      'background only';
      const presented = event.detail?.presented === true;
      if (presented) {
        if (openRef.current) {
          onEnteredRef.current?.();
        }
        return;
      }
      if (!openRef.current) {
        setMounted(false);
        onExitedRef.current?.();
      }
    },
    [],
  );

  const dismissFromDrag = useCallback(() => {
    'background only';
    if (openRef.current) {
      onOpenChangeRef.current(false, 'drag');
    }
  }, []);

  const trackRootHeight = useCallback((event: LayoutChangeEvent) => {
    'background only';
    const rootHeight = event.detail.height;
    setLayout((current) =>
      current.rootHeight === rootHeight ? current : { ...current, rootHeight },
    );
  }, []);

  const trackContentHeight = useCallback((event: LayoutChangeEvent) => {
    'background only';
    const contentHeight = event.detail.height;
    setLayout((current) =>
      current.contentHeight === contentHeight
        ? current
        : { ...current, contentHeight },
    );
  }, []);

  if (!rendered) {
    return null;
  }

  return (
    <predictive-back-overlay
      className={className}
      style={{ ...ROOT_STYLE, ...style }}
      target-id={targetId}
      backdrop-color={backdropColor}
      motion={motion}
      presented={open}
      animate-presence={animated}
      drag-to-dismiss={dragToDismiss && motion === 'sheet'}
      drag-dismiss-threshold={Math.max(
        0.05,
        Math.min(0.9, dragDismissThreshold),
      )}
      content-height-ratio={
        layout.rootHeight > 0
          ? Math.max(0, Math.min(1, layout.contentHeight / layout.rootHeight))
          : 0
      }
      bindlayoutchange={trackRootHeight}
      bindoverlaytransitionend={handleTransitionEnd}
      binddragdismiss={dismissFromDrag}
      bindbackdroppress={dismissFromBackdrop}
    >
      <view style={CHILD_WRAPPER_STYLE}>
        <view
          className={contentClassName}
          style={{ ...CONTENT_STYLE, ...contentStyle }}
          bindlayoutchange={trackContentHeight}
        >
          {children}
        </view>
      </view>
    </predictive-back-overlay>
  );
}
