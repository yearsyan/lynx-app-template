import { completeNativeCall, requireNativeModule } from './bridge.generated.js';

export * from './native.generated.js';

function requireNavigationModule() {
  'background only';
  return requireNativeModule();
}

// ---------------------------------------------------------------------------
// Route navigation
// ---------------------------------------------------------------------------

export type StatusBarStyle = 'dark-content' | 'light-content';

function normalizeStatusBarStyle(style: StatusBarStyle): StatusBarStyle {
  'background only';
  if (style !== 'dark-content' && style !== 'light-content') {
    throw new Error(`Invalid status bar style: ${String(style)}`);
  }
  return style;
}

export type RoutePresentation = 'push' | 'sheet';
export type RouteAnimation = 'default' | 'fade' | 'none';

export interface RouteOptions {
  bundle: string;
  presentation?: RoutePresentation;
  transparent?: boolean;
  /** Foreground style for status-bar icons and text on the destination page. */
  statusBarStyle?: StatusBarStyle;
  /**
   * Native open/close transition. 'default' keeps each platform's standard
   * push transition, 'fade' cross-fades, and 'none' opens/closes instantly.
   */
  animation?: RouteAnimation;
  params?: Record<string, unknown>;
}

function normalizeRouteAnimation(animation: RouteAnimation): RouteAnimation {
  'background only';
  if (animation !== 'default' && animation !== 'fade' && animation !== 'none') {
    throw new Error(`Invalid route animation: ${String(animation)}`);
  }
  return animation;
}

export const router = {
  open(options: RouteOptions): Promise<void> {
    'background only';
    const normalized: RouteOptions = {
      bundle: options.bundle,
      presentation: options.presentation ?? 'push',
      transparent: options.transparent ?? options.presentation === 'sheet',
      statusBarStyle: normalizeStatusBarStyle(
        options.statusBarStyle ?? 'dark-content',
      ),
      animation: normalizeRouteAnimation(options.animation ?? 'default'),
      params: options.params ?? {},
    };
    return completeNativeCall((callback) =>
      requireNavigationModule().open(normalized, callback),
    );
  },

  close(): Promise<void> {
    'background only';
    return completeNativeCall((callback) =>
      requireNavigationModule().close(callback),
    );
  },

  /**
   * Opens a URL through the system router. Any app that registered the
   * scheme can handle it, including this app's own scheme pages —
   * `lynxapp://main`, `weixin://`, `imeituan://`, `https://…` and so on.
   */
  openURL(url: string): Promise<void> {
    'background only';
    return completeNativeCall((callback) =>
      requireNavigationModule().openURL(url, callback),
    );
  },
};

// ---------------------------------------------------------------------------
// Back interception
// ---------------------------------------------------------------------------

export type BackPlatform = 'android' | 'ios' | 'harmony';
export type BackPhase = 'start' | 'progress' | 'cancel' | 'commit';
export type BackSource = 'system' | 'gesture' | 'button';
export type BackEdge = 'left' | 'right' | 'none';

export interface BackEvent {
  platform: BackPlatform;
  phase: BackPhase;
  progress: number;
  source: BackSource;
  edge: BackEdge;
  touchX: number;
  touchY: number;
  /** Internal routing identity pinned by native code for one Back gesture. */
  interceptorId?: string;
  /** Monotonic native gesture identity, useful when diagnosing event order. */
  gestureId?: number;
}

export type BackListener = (event: BackEvent) => void;

export interface BackInterceptorRegistration {
  /** Resolves after the current LynxView has enabled native interception. */
  readonly ready: Promise<void>;
  /** Removes this interceptor. Calling remove more than once is safe. */
  remove(): void;
}

export interface BackInterceptorOptions {
  /**
   * Native animation target registered by PredictiveBackOverlay. Headless
   * interceptors should leave this empty so they remain above visual targets.
   */
  animationTargetId?: string;
}

export const BACK_EVENT = 'back';

function isBackEvent(value: unknown): value is BackEvent {
  'background only';
  if (typeof value !== 'object' || value === null) {
    return false;
  }
  const event = value as Partial<BackEvent>;
  return (
    (event.platform === 'android' ||
      event.platform === 'ios' ||
      event.platform === 'harmony') &&
    (event.phase === 'start' ||
      event.phase === 'progress' ||
      event.phase === 'cancel' ||
      event.phase === 'commit') &&
    typeof event.progress === 'number' &&
    Number.isFinite(event.progress) &&
    event.progress >= 0 &&
    event.progress <= 1 &&
    (event.source === 'system' ||
      event.source === 'gesture' ||
      event.source === 'button') &&
    (event.edge === 'left' ||
      event.edge === 'right' ||
      event.edge === 'none') &&
    typeof event.touchX === 'number' &&
    Number.isFinite(event.touchX) &&
    typeof event.touchY === 'number' &&
    Number.isFinite(event.touchY) &&
    (event.interceptorId === undefined ||
      typeof event.interceptorId === 'string') &&
    (event.gestureId === undefined ||
      (typeof event.gestureId === 'number' &&
        Number.isFinite(event.gestureId) &&
        event.gestureId >= 0))
  );
}

export const back = {
  /** Enables or disables interception for this LynxView. */
  setEnabled(enabled: boolean): Promise<void> {
    'background only';
    return completeNativeCall((callback) =>
      requireNavigationModule().setEnabled(enabled, callback),
    );
  },

  /** Subscribes to validated native Back lifecycle events. */
  addListener(listener: BackListener): () => void {
    'background only';
    const emitter = lynx.getJSModule('GlobalEventEmitter');
    const adapter = (payload: unknown) => {
      'background only';
      if (isBackEvent(payload)) {
        listener(payload);
      }
    };
    emitter.addListener(BACK_EVENT, adapter);
    return () => {
      'background only';
      emitter.removeListener(BACK_EVENT, adapter);
    };
  },
};

interface BackInterceptorEntry {
  id: string;
  listener: BackListener;
  animationTargetId: string;
  removed: boolean;
}

const backInterceptors: BackInterceptorEntry[] = [];
const backInterceptorsById = new Map<string, BackInterceptorEntry>();
let activeBackInterceptor: BackInterceptorEntry | null = null;
let removeBackStackListener: (() => void) | null = null;
let nextBackInterceptorId = 0;
let nextBackStackRevision = 0;
let appliedBackStackRevision = 0;

interface BackStackConfiguration {
  enabled: boolean;
  interceptorId: string;
  targetId: string;
  revision: number;
}

let desiredBackStackConfiguration: BackStackConfiguration = {
  enabled: false,
  interceptorId: '',
  targetId: '',
  revision: 0,
};
let backStackSync: Promise<void> = Promise.resolve();

function topBackInterceptor(): BackInterceptorEntry | null {
  'background only';
  return backInterceptors[backInterceptors.length - 1] ?? null;
}

function dispatchBackStackEvent(event: BackEvent): void {
  'background only';
  if (event.phase === 'start' || activeBackInterceptor === null) {
    activeBackInterceptor = event.interceptorId
      ? (backInterceptorsById.get(event.interceptorId) ?? null)
      : topBackInterceptor();
  }

  const target = activeBackInterceptor;
  const isTerminal = event.phase === 'cancel' || event.phase === 'commit';
  try {
    // Pin every phase to the interceptor that received start. If that popup
    // disappears mid-gesture, do not leak the remaining phases underneath it.
    if (target !== null && !target.removed) {
      target.listener(event);
    }
  } finally {
    if (isTerminal) {
      activeBackInterceptor = null;
    }
  }
}

function ensureBackStackListener(): void {
  'background only';
  if (removeBackStackListener === null) {
    removeBackStackListener = back.addListener(dispatchBackStackEvent);
  }
}

function reportBackStackError(error: unknown): void {
  'background only';
  const message = error instanceof Error ? error.message : String(error);
  console.error(`Unable to synchronize native Back: ${message}`);
}

function configureNativeBack(
  configuration: BackStackConfiguration,
): Promise<void> {
  'background only';
  return completeNativeCall((callback) =>
    requireNavigationModule().configure(
      configuration.enabled,
      configuration.interceptorId,
      configuration.targetId,
      configuration.revision,
      callback,
    ),
  );
}

function reconcileBackStack(): Promise<void> {
  'background only';
  const top = topBackInterceptor();
  desiredBackStackConfiguration = {
    enabled: top !== null,
    interceptorId: top?.id ?? '',
    targetId: top?.animationTargetId ?? '',
    revision: ++nextBackStackRevision,
  };
  backStackSync = backStackSync
    .catch(() => {})
    .then(async () => {
      'background only';
      while (
        appliedBackStackRevision < desiredBackStackConfiguration.revision
      ) {
        const configuration = desiredBackStackConfiguration;
        await configureNativeBack(configuration);
        appliedBackStackRevision = configuration.revision;
      }
    });
  return backStackSync;
}

/**
 * LIFO dispatcher for nested Lynx UI such as dropdowns, dialogs and sheets.
 * Native interception remains enabled until the final entry is removed.
 */
export const backStack = {
  addInterceptor(
    listener: BackListener,
    options: BackInterceptorOptions = {},
  ): BackInterceptorRegistration {
    'background only';
    ensureBackStackListener();
    const entry: BackInterceptorEntry = {
      id: `back-interceptor-${++nextBackInterceptorId}`,
      listener,
      animationTargetId: options.animationTargetId ?? '',
      removed: false,
    };
    backInterceptors.push(entry);
    backInterceptorsById.set(entry.id, entry);
    const ready = reconcileBackStack();
    ready.catch(reportBackStackError);

    return {
      ready,
      remove(): void {
        'background only';
        if (entry.removed) {
          return;
        }
        entry.removed = true;
        backInterceptorsById.delete(entry.id);
        const index = backInterceptors.lastIndexOf(entry);
        if (index >= 0) {
          backInterceptors.splice(index, 1);
        }
        reconcileBackStack().catch(reportBackStackError);
      },
    };
  },

  get size(): number {
    'background only';
    return backInterceptors.length;
  },
};
