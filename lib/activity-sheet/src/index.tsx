import {
  type ReactNode,
  useCallback,
  useEffect,
  useInitData,
  useRef,
  useState,
} from '@lynx-js/react';
import {
  type NativeBackEdge,
  type NativeBackEvent,
  type NativeBackPhase,
  type NativeRouteAnimation,
  type NativeStatusBarStyle,
  nativeBackStack,
  nativeRouter,
  readSafeAreaInsets,
} from '@lynx-template/native-bridge';

import './style.css';

export const ACTIVITY_BOTTOM_SHEET_TRANSITION_MS = 180;

export interface OpenActivityBottomSheetOptions {
  bundle: string;
  statusBarStyle?: NativeStatusBarStyle;
  /** Native transition behind the sheet's own panel animation. */
  animation?: NativeRouteAnimation;
  params?: Record<string, unknown>;
}

export interface UseActivityBottomSheetOptions {
  /** Override only when the sheet is hosted outside a native routed page. */
  closeRoute?: () => Promise<void>;
  onBackEvent?: (event: NativeBackEvent) => void;
  onError?: (error: Error) => void;
}

export interface ActivityBottomSheetController {
  readonly edge: NativeBackEdge;
  readonly percentage: number;
  readonly phase: NativeBackPhase | 'ready' | 'error';
  readonly presented: boolean;
  readonly progress: number;
  readonly tracking: boolean;
  dismiss(): void;
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
}

export function openActivityBottomSheet(
  options: OpenActivityBottomSheetOptions,
): Promise<void> {
  'background only';
  return nativeRouter.open({
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
  const closeRoute = options.closeRoute ?? nativeRouter.close;
  const [presented, setPresented] = useState(false);
  const [progress, setProgress] = useState(0);
  const [phase, setPhase] = useState<NativeBackPhase | 'ready' | 'error'>(
    'ready',
  );
  const [edge, setEdge] = useState<NativeBackEdge>('none');
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
    const registration = nativeBackStack.addInterceptor((event) => {
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

  return {
    edge,
    percentage: Math.round(progress * 100),
    phase,
    presented,
    progress,
    tracking,
    dismiss,
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
  } = props;
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

  return (
    <view className={pageClasses}>
      <view
        className="ActivityBottomSheet__backdrop"
        style={{ opacity: backdropOpacity }}
        bindtap={handleBackdropTap}
      />
      <view
        className={panelClasses}
        style={{
          paddingBottom: `${safeBottomPadding}px`,
          transform: `translateY(${translateY}%)`,
        }}
      >
        {showGrabber ? <view className="ActivityBottomSheet__grabber" /> : null}
        {children}
      </view>
    </view>
  );
}
