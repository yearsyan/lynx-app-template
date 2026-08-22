import {
  completeNativeCall,
  decodeNativeEnvelope,
  requireNativeModule,
} from './bridge.generated.js';

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

/**
 * Native open/close transition. 'default' keeps each platform's standard push
 * transition, 'fade' cross-fades, 'none' opens/closes instantly, and 'present'
 * snapshots the current page as the new page's backdrop and plays an iOS-like
 * present choreography (previous page shrinks, content slides in).
 */
export type RouteAnimation = 'default' | 'fade' | 'none' | 'present';

/**
 * Fine-tuning for `animation: 'present'` routes; ignored by other animations.
 */
export interface RoutePresentContentAnimationOptions {
  /**
   * Fades the new page between transparent and opaque. Default false.
   */
  opacity?: boolean;
  /**
   * Moves the new page from/to one full viewport below the screen. Its first
   * entering frame (and last exiting frame) therefore has 0 visible area.
   * Default true.
   */
  push?: boolean;
}

export interface RoutePresentOptions {
  /**
   * Scrim color layered over the snapshot backdrop, '#AARRGGBB' (alpha first).
   * Defaults to '#59000000' (35% black); '#00000000' disables the dimming.
   */
  scrimColor?: string;
  /**
   * Previous-page choreography: the snapshot backdrop shrinks, drops and gains
   * rounded corners on open (reversed on close). With false the snapshot stays
   * static behind the content. Default true.
   */
  backdropTransition?: boolean;
  /**
   * New-page entering choreography. `opacity` defaults to false and `push`
   * defaults to true.
   */
  enter?: RoutePresentContentAnimationOptions;
  /**
   * New-page exiting choreography, configured independently from `enter`.
   * `opacity` defaults to false and `push` defaults to true.
   */
  exit?: RoutePresentContentAnimationOptions;
  /**
   * Legacy switch for the `push` default of both `enter` and `exit`. Explicit
   * phase-level `push` values win. Prefer `enter` / `exit` for new code.
   *
   * @deprecated Use `enter.push` and `exit.push`.
   */
  contentTransition?: boolean;
  /**
   * Blurs the snapshot backdrop and captures it at reduced resolution — no
   * pixel alignment with the previous page is attempted, which keeps the
   * capture cheap. Default false.
   */
  backdropBlur?: boolean;
  /**
   * Lets an iOS leading-edge swipe interactively drive the configured exit
   * choreography. With the default exit options the page follows the gesture
   * downward while the snapshot expands; cancellation springs it back.
   * Default false.
   */
  iosSwipeDown?: boolean;
  /**
   * Lets Android predictive Back progress interactively drive the configured
   * exit choreography. With the default exit options the page follows the
   * gesture downward; cancellation springs it back. Default false.
   */
  androidPredictiveBackDown?: boolean;
}

export interface RouteOptions {
  bundle: string;
  /** Foreground style for status-bar icons and text on the destination page. */
  statusBarStyle?: StatusBarStyle;
  animation?: RouteAnimation;
  present?: RoutePresentOptions;
  params?: Record<string, unknown>;
}

/** Result payload a route hands back through `closeWithResult`. */
export type RouteResult = Record<string, unknown>;

function normalizeRouteOptions(options: RouteOptions): RouteOptions {
  'background only';
  const animation = normalizeRouteAnimation(options.animation ?? 'default');
  const present = normalizePresentOptions(options.present, animation);
  return {
    bundle: options.bundle,
    statusBarStyle: normalizeStatusBarStyle(
      options.statusBarStyle ?? 'dark-content',
    ),
    animation,
    ...(present !== undefined ? { present } : {}),
    params: options.params ?? {},
  };
}

function normalizeRouteAnimation(animation: RouteAnimation): RouteAnimation {
  'background only';
  if (
    animation !== 'default' &&
    animation !== 'fade' &&
    animation !== 'none' &&
    animation !== 'present'
  ) {
    throw new Error(`Invalid route animation: ${String(animation)}`);
  }
  return animation;
}

const SCRIM_COLOR_PATTERN = /^#[0-9a-fA-F]{8}$/;

const PRESENT_BOOLEAN_FLAGS = [
  'backdropTransition',
  'contentTransition',
  'backdropBlur',
  'iosSwipeDown',
  'androidPredictiveBackDown',
] as const;

const PRESENT_CONTENT_BOOLEAN_FLAGS = ['opacity', 'push'] as const;

function normalizePresentContentAnimation(
  phase: 'enter' | 'exit',
  animation: RoutePresentContentAnimationOptions | undefined,
): RoutePresentContentAnimationOptions | undefined {
  'background only';
  if (animation === undefined) {
    return undefined;
  }
  if (
    animation === null ||
    typeof animation !== 'object' ||
    Array.isArray(animation)
  ) {
    throw new Error(`Invalid present ${phase}: want an options object`);
  }
  for (const flag of PRESENT_CONTENT_BOOLEAN_FLAGS) {
    const value = animation[flag];
    if (value !== undefined && typeof value !== 'boolean') {
      throw new Error(`Invalid present ${phase}.${flag}: ${String(value)}`);
    }
  }
  return {
    opacity: animation.opacity,
    push: animation.push,
  };
}

function normalizePresentOptions(
  present: RoutePresentOptions | undefined,
  animation: RouteAnimation,
): RoutePresentOptions | undefined {
  'background only';
  if (present === undefined || animation !== 'present') {
    return undefined;
  }
  if (
    present.scrimColor !== undefined &&
    !SCRIM_COLOR_PATTERN.test(present.scrimColor)
  ) {
    throw new Error(
      `Invalid present scrim color: ${present.scrimColor} (want '#AARRGGBB')`,
    );
  }
  for (const flag of PRESENT_BOOLEAN_FLAGS) {
    const value = present[flag];
    if (value !== undefined && typeof value !== 'boolean') {
      throw new Error(`Invalid present ${flag}: ${String(value)}`);
    }
  }
  const enter = normalizePresentContentAnimation('enter', present.enter);
  const exit = normalizePresentContentAnimation('exit', present.exit);
  return {
    scrimColor: present.scrimColor,
    backdropTransition: present.backdropTransition,
    ...(enter !== undefined ? { enter } : {}),
    ...(exit !== undefined ? { exit } : {}),
    contentTransition: present.contentTransition,
    backdropBlur: present.backdropBlur,
    iosSwipeDown: present.iosSwipeDown,
    androidPredictiveBackDown: present.androidPredictiveBackDown,
  };
}

export const router = {
  open(options: RouteOptions): Promise<void> {
    'background only';
    const normalized = normalizeRouteOptions(options);
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

  /**
   * Opens a route and waits for it to close. The promise resolves when the
   * opened page disappears: with the object passed to `closeWithResult`, or
   * `undefined` when it closed without one (plain `close`, system Back).
   * Rejects when the route failed to open.
   */
  openForResult<T extends RouteResult = RouteResult>(
    options: RouteOptions,
  ): Promise<T | undefined> {
    'background only';
    const normalized = normalizeRouteOptions(options);
    return new Promise<T | undefined>((resolve, reject) => {
      try {
        requireNavigationModule().openForResult(normalized, (resultJSON) => {
          'background only';
          try {
            const envelope = decodeNativeEnvelope(
              resultJSON,
              'router.openForResult',
            );
            if (
              typeof envelope.error === 'string' &&
              envelope.error.length > 0
            ) {
              reject(new Error(envelope.error));
              return;
            }
            const value = envelope.value;
            if (value === undefined || value === null) {
              resolve(undefined);
              return;
            }
            if (typeof value !== 'object' || Array.isArray(value)) {
              reject(
                new Error('router.openForResult returned an invalid result'),
              );
              return;
            }
            resolve(value as T);
          } catch (error) {
            reject(error instanceof Error ? error : new Error(String(error)));
          }
        });
      } catch (error) {
        reject(error instanceof Error ? error : new Error(String(error)));
      }
    });
  },

  /**
   * Closes the current route, delivering `result` to the opener's pending
   * `openForResult` promise. On a route that was not opened for a result the
   * result is dropped and the route closes normally.
   */
  closeWithResult(result: RouteResult): Promise<void> {
    'background only';
    if (
      typeof result !== 'object' ||
      result === null ||
      Array.isArray(result)
    ) {
      return Promise.reject(
        new Error('Invalid route result: want an options object'),
      );
    }
    return completeNativeCall((callback) =>
      requireNavigationModule().closeWithResult(result, callback),
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
