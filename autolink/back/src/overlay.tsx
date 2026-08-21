import {
  type Dispatch,
  type ReactNode,
  type SetStateAction,
  useCallback,
  useEffect,
  useRef,
  useState,
} from '@lynx-js/react';
import type { CSSProperties, StandardProps } from '@lynx-js/types';

import { type BackEvent, type BackListener, backStack } from './index.js';

export const PREDICTIVE_BACK_OVERLAY_ELEMENT_NAME =
  'predictive-back-overlay' as const;

export type PredictiveBackOverlayMotion = 'sheet' | 'horizontal' | 'none';
export type PredictiveBackOverlayDismissReason = 'back' | 'backdrop';

export interface PredictiveBackOverlayElementProps extends StandardProps {
  children?: ReactNode;
  'target-id': string;
  'backdrop-color'?: string;
  motion?: PredictiveBackOverlayMotion;
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
  dismissOnBackdropPress?: boolean;
  onBackEvent?: BackListener;
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
    dismissOnBackdropPress = true,
    onBackEvent,
    className,
    style,
    contentClassName,
    contentStyle,
  } = props;
  const [targetId] = useState(
    () => `predictive-back-overlay-${++nextPredictiveBackOverlayId}`,
  );
  const onOpenChangeRef = useRef(onOpenChange);
  const onBackEventRef = useRef(onBackEvent);

  useEffect(() => {
    onOpenChangeRef.current = onOpenChange;
    onBackEventRef.current = onBackEvent;
  });

  useEffect(() => {
    if (!open) {
      return;
    }
    const registration = backStack.addInterceptor(
      (event: BackEvent) => {
        'background only';
        onBackEventRef.current?.(event);
        if (event.phase === 'commit') {
          onOpenChangeRef.current(false, 'back');
        }
      },
      { animationTargetId: targetId },
    );
    return registration.remove;
  }, [open, targetId]);

  const dismissFromBackdrop = useCallback(() => {
    'background only';
    if (dismissOnBackdropPress) {
      onOpenChangeRef.current(false, 'backdrop');
    }
  }, [dismissOnBackdropPress]);

  if (!open) {
    return null;
  }

  return (
    <predictive-back-overlay
      className={className}
      style={{ ...ROOT_STYLE, ...style }}
      target-id={targetId}
      backdrop-color={backdropColor}
      motion={motion}
      bindtap={dismissFromBackdrop}
    >
      <view
        className={contentClassName}
        style={{ ...CONTENT_STYLE, ...contentStyle }}
        catchtap={() => {
          'background only';
        }}
      >
        {children}
      </view>
    </predictive-back-overlay>
  );
}
