import {
  type ReactNode,
  runOnBackground,
  useCallback,
  useEffect,
  useInitData,
  useMainThreadRef,
  useRef,
  useState,
} from '@lynx-js/react';
import type {
  LayoutChangeDetailEvent,
  MainThread,
  Target,
} from '@lynx-js/types';
import {
  type BackEdge,
  type BackEvent,
  type BackPhase,
  backStack,
} from '@lynx-template/autolink-back';
import { readSafeAreaInsets } from '@lynx-template/autolink-device-info';
import {
  type RouteAnimation,
  router,
  type StatusBarStyle,
} from '@lynx-template/autolink-router';

import './style.css';

export const ACTIVITY_BOTTOM_SHEET_TRANSITION_MS = 180;

const DEFAULT_DISMISS_THRESHOLD = 0.35;
const DEFAULT_FLING_VELOCITY_PX_PER_MS = 0.6;
/** Used for drag progress only until the panel reports its laid-out height. */
const FALLBACK_PANEL_HEIGHT_PX = 320;
/** Finger travel before a panel touch becomes a drag, so taps pass through. */
const DRAG_ACTIVATION_PX = 8;

interface PanelDragState {
  /** Finger is down but has not necessarily become a drag yet. */
  armed: boolean;
  dragging: boolean;
  touchId: number;
  startY: number;
  lastY: number;
  lastTime: number;
  velocity: number;
  distance: number;
}

export interface OpenActivityBottomSheetOptions {
  bundle: string;
  statusBarStyle?: StatusBarStyle;
  /** Native transition behind the sheet's own panel animation. */
  animation?: RouteAnimation;
  params?: Record<string, unknown>;
}

export interface UseActivityBottomSheetOptions {
  /** Override only when the sheet is hosted outside a native routed page. */
  closeRoute?: () => Promise<void>;
  onBackEvent?: (event: BackEvent) => void;
  onError?: (error: Error) => void;
}

export interface ActivityBottomSheetController {
  readonly edge: BackEdge;
  readonly percentage: number;
  readonly phase: BackPhase | 'ready' | 'error';
  readonly presented: boolean;
  readonly progress: number;
  readonly tracking: boolean;
  dismiss(): void;
  /**
   * Settles an interactive panel drag started on the main thread. `commit`
   * dismisses the sheet; otherwise the sheet returns to its resting position.
   */
  endDrag(commit: boolean): void;
}

export interface ActivityBottomSheetProps {
  children?: ReactNode;
  controller: ActivityBottomSheetController;
  /** Extra content padding above the native bottom safe area. Defaults to 30px. */
  bottomPadding?: number;
  closeOnBackdropTap?: boolean;
  pageClassName?: string;
  panelClassName?: string;
  /** Maximum opacity of the black backdrop. Defaults to 0.28. */
  scrimOpacity?: number;
  showGrabber?: boolean;
  /**
   * Allow dismissing the sheet by dragging its panel downward; the panel
   * follows the finger on the main thread. Defaults to true. Note: the drag
   * does not negotiate with nested scrollable content yet, so prefer a fixed
   * (non-scrolling) sheet body.
   */
  dragToDismiss?: boolean;
  /** Drag distance, as a fraction of the panel height, that commits a dismiss. Defaults to 0.35. */
  dismissThreshold?: number;
  /** Downward fling velocity in px/ms that commits a dismiss. Defaults to 0.6. */
  flingVelocity?: number;
}

export function openActivityBottomSheet(
  options: OpenActivityBottomSheetOptions,
): Promise<void> {
  'background only';
  return router.open({
    bundle: options.bundle,
    presentation: 'sheet',
    transparent: true,
    statusBarStyle: options.statusBarStyle ?? 'dark-content',
    animation: options.animation,
    params: options.params,
  });
}

export function useActivityBottomSheet(
  options: UseActivityBottomSheetOptions = {},
): ActivityBottomSheetController {
  const closeRoute = options.closeRoute ?? router.close;
  const [presented, setPresented] = useState(false);
  const [progress, setProgress] = useState(0);
  const [phase, setPhase] = useState<BackPhase | 'ready' | 'error'>('ready');
  const [edge, setEdge] = useState<BackEdge>('none');
  const [tracking, setTracking] = useState(false);
  const closeTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  const reportError = useCallback(
    (error: Error) => {
      'background only';
      setPhase('error');
      options.onError?.(error);
    },
    [options.onError],
  );

  const dismiss = useCallback(() => {
    'background only';
    if (closeTimer.current !== null) {
      return;
    }

    setPhase('commit');
    setTracking(false);
    setProgress(1);
    closeTimer.current = setTimeout(() => {
      closeTimer.current = null;
      closeRoute().catch((error: Error) => {
        setProgress(0);
        reportError(error);
      });
    }, ACTIVITY_BOTTOM_SHEET_TRANSITION_MS);
  }, [closeRoute, reportError]);

  useEffect(() => {
    'background only';
    const frame = requestAnimationFrame(() => setPresented(true));
    return () => cancelAnimationFrame(frame);
  }, []);

  useEffect(() => {
    'background only';
    return () => {
      if (closeTimer.current !== null) {
        clearTimeout(closeTimer.current);
      }
    };
  }, []);

  useEffect(() => {
    'background only';
    const registration = backStack.addInterceptor((event) => {
      'background only';
      setPhase(event.phase);
      setEdge(event.edge);
      options.onBackEvent?.(event);

      if (event.phase === 'start' || event.phase === 'progress') {
        setTracking(true);
        setProgress(event.progress);
      } else if (event.phase === 'cancel') {
        setTracking(false);
        setProgress(0);
      } else {
        dismiss();
      }
    });
    registration.ready.catch(reportError);
    return registration.remove;
  }, [dismiss, options.onBackEvent, reportError]);

  const endDrag = useCallback(
    (commit: boolean) => {
      'background only';
      if (closeTimer.current !== null) {
        return;
      }
      if (commit) {
        dismiss();
      } else {
        setPhase('cancel');
        setEdge('none');
        setTracking(false);
        setProgress(0);
      }
    },
    [dismiss],
  );

  return {
    edge,
    percentage: Math.round(progress * 100),
    phase,
    presented,
    progress,
    tracking,
    dismiss,
    endDrag,
  };
}

export function ActivityBottomSheet(props: ActivityBottomSheetProps) {
  const {
    children,
    controller,
    bottomPadding = 30,
    closeOnBackdropTap = true,
    pageClassName,
    panelClassName,
    scrimOpacity = 0.28,
    showGrabber = true,
    dragToDismiss = true,
    dismissThreshold = DEFAULT_DISMISS_THRESHOLD,
    flingVelocity = DEFAULT_FLING_VELOCITY_PX_PER_MS,
  } = props;
  const [panelHeight, setPanelHeight] = useState(0);
  const insets = readSafeAreaInsets(useInitData());
  const safeBottomPadding = Math.max(0, bottomPadding) + insets.bottom;
  const safeScrimOpacity = Math.max(0, Math.min(1, scrimOpacity));
  const translateY = controller.presented ? controller.percentage : 100;
  const backdropOpacity = controller.presented
    ? (safeScrimOpacity * (1 - controller.progress)).toFixed(3)
    : '0';
  const pageClasses = pageClassName
    ? `ActivityBottomSheet ${pageClassName}`
    : 'ActivityBottomSheet';
  const panelClasses = [
    'ActivityBottomSheet__panel',
    controller.tracking ? 'ActivityBottomSheet__panel--tracking' : '',
    panelClassName ?? '',
  ]
    .filter(Boolean)
    .join(' ');

  const handleBackdropTap = useCallback(() => {
    'background only';
    if (closeOnBackdropTap) {
      controller.dismiss();
    }
  }, [closeOnBackdropTap, controller]);

  const handlePanelLayout = useCallback(
    (event: LayoutChangeDetailEvent<Target>) => {
      'background only';
      const height = event.detail?.height;
      if (typeof height === 'number' && height > 0) {
        setPanelHeight((previous) =>
          Math.abs(previous - height) < 0.5 ? previous : height,
        );
      }
    },
    [],
  );

  // The drag runs entirely on the main thread so the panel tracks the finger
  // every frame. The background thread is only notified once the gesture is
  // released, which keeps JSX style flushes from racing the direct style
  // mutations below.
  const panelElement = useMainThreadRef<MainThread.Element | null>(null);
  const backdropElement = useMainThreadRef<MainThread.Element | null>(null);
  const dragState = useMainThreadRef<PanelDragState>({
    armed: false,
    dragging: false,
    touchId: -1,
    startY: 0,
    lastY: 0,
    lastTime: 0,
    velocity: 0,
    distance: 0,
  });
  const finishDrag = (commit: boolean) => {
    'background only';
    controller.endDrag(commit);
  };

  const transitionMs = ACTIVITY_BOTTOM_SHEET_TRANSITION_MS;
  // Captured values cross into the worklet by value: call .toFixed() here on
  // the background thread, since method calls on captured numbers are not
  // invokable inside main-thread worklets.
  const restingScrimOpacity = safeScrimOpacity.toFixed(3);
  const dragInteractive =
    dragToDismiss &&
    controller.presented &&
    !controller.tracking &&
    controller.phase !== 'commit' &&
    controller.phase !== 'error';
  const referenceHeight =
    panelHeight > 0 ? panelHeight : FALLBACK_PANEL_HEIGHT_PX;

  const handleDragStart = (event: MainThread.TouchEvent) => {
    'main thread';
    if (!dragInteractive) {
      return;
    }
    const touch = event.touches[0];
    if (!touch) {
      return;
    }
    const drag = dragState.current;
    // Only arm here: the gesture becomes a drag once the finger travels past
    // the activation slop in handleDragMove, so plain taps on panel content
    // never touch styles or report a spurious cancel.
    drag.armed = true;
    drag.dragging = false;
    drag.touchId = touch.identifier;
    drag.startY = touch.clientY;
    drag.lastY = touch.clientY;
    drag.lastTime = event.timestamp;
    drag.velocity = 0;
    drag.distance = 0;
  };

  const handleDragMove = (event: MainThread.TouchEvent) => {
    'main thread';
    const drag = dragState.current;
    if (!drag.armed) {
      return;
    }
    let touch = event.touches[0];
    for (let index = 0; index < event.touches.length; index += 1) {
      const candidate = event.touches[index];
      if (candidate && candidate.identifier === drag.touchId) {
        touch = candidate;
        break;
      }
    }
    if (!touch) {
      return;
    }
    if (!drag.dragging) {
      if (touch.clientY - drag.startY <= DRAG_ACTIVATION_PX) {
        return;
      }
      // Activate, re-anchoring so the panel does not jump by the slop amount.
      drag.dragging = true;
      drag.startY = touch.clientY;
      drag.lastY = touch.clientY;
      drag.lastTime = event.timestamp;
      panelElement.current?.setStyleProperty('transition', 'none');
      backdropElement.current?.setStyleProperty('transition', 'none');
      return;
    }
    const distance = Math.max(0, touch.clientY - drag.startY);
    const elapsed = event.timestamp - drag.lastTime;
    if (elapsed > 0) {
      drag.velocity = (touch.clientY - drag.lastY) / elapsed;
    }
    drag.lastY = touch.clientY;
    drag.lastTime = event.timestamp;
    drag.distance = distance;

    panelElement.current?.setStyleProperty(
      'transform',
      `translateY(${distance}px)`,
    );
    const progress = Math.min(1, distance / referenceHeight);
    const opacity = safeScrimOpacity * (1 - progress);
    backdropElement.current?.setStyleProperty('opacity', opacity.toFixed(3));
  };

  const handleDragEnd = (event: MainThread.TouchEvent) => {
    'main thread';
    const drag = dragState.current;
    if (!drag.armed) {
      return;
    }
    drag.armed = false;
    if (!drag.dragging) {
      // Never became a drag: a tap (or upward pull) on the panel.
      return;
    }
    drag.dragging = false;

    const progress = Math.min(1, drag.distance / referenceHeight);
    const commit =
      event.type === 'touchend' &&
      (progress >= dismissThreshold ||
        (drag.velocity >= flingVelocity && drag.distance > 40));

    // Settle with a CSS transition whose target matches the JSX-driven style
    // the background thread flushes once `reportDragEnd` lands, so whichever
    // wins the race the resting state is identical.
    panelElement.current?.setStyleProperties({
      transition: `transform ${transitionMs}ms ease-out`,
      transform: commit ? 'translateY(100%)' : 'translateY(0%)',
    });
    backdropElement.current?.setStyleProperties({
      transition: `opacity ${transitionMs}ms ease-out`,
      opacity: commit ? '0' : restingScrimOpacity,
    });
    // runOnBackground must be called from inside the worklet: invoking it
    // while rendering on the background thread throws.
    runOnBackground(finishDrag)(commit);
  };

  return (
    <view className={pageClasses}>
      <view
        className="ActivityBottomSheet__backdrop"
        style={{ opacity: backdropOpacity }}
        bindtap={handleBackdropTap}
        main-thread:ref={backdropElement}
      />
      <view
        className={panelClasses}
        style={{
          paddingBottom: `${safeBottomPadding}px`,
          transform: `translateY(${translateY}%)`,
        }}
        bindlayoutchange={handlePanelLayout}
        main-thread:ref={panelElement}
        main-thread:bindtouchstart={handleDragStart}
        main-thread:bindtouchmove={handleDragMove}
        main-thread:bindtouchend={handleDragEnd}
        main-thread:bindtouchcancel={handleDragEnd}
      >
        {showGrabber ? <view className="ActivityBottomSheet__grabber" /> : null}
        {children}
      </view>
    </view>
  );
}
