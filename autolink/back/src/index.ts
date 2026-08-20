import { completeNativeCall, requireNativeModule } from './bridge.generated.js';

export * from './native.generated.js';

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
}

export type BackListener = (event: BackEvent) => void;

export interface BackInterceptorRegistration {
  /** Resolves after the current LynxView has enabled native interception. */
  readonly ready: Promise<void>;
  /** Removes this interceptor. Calling remove more than once is safe. */
  remove(): void;
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
    Number.isFinite(event.touchY)
  );
}

function requireBackModule() {
  'background only';
  return requireNativeModule();
}

export const back = {
  /** Enables or disables interception for this LynxView. */
  setEnabled(enabled: boolean): Promise<void> {
    'background only';
    return completeNativeCall((callback) =>
      requireBackModule().setEnabled(enabled, callback),
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
  listener: BackListener;
  removed: boolean;
}

const backInterceptors: BackInterceptorEntry[] = [];
let activeBackInterceptor: BackInterceptorEntry | null = null;
let removeBackStackListener: (() => void) | null = null;
let backStackEnabled = false;
let backStackDesiredEnabled = false;
let backStackSync: Promise<void> = Promise.resolve();

function topBackInterceptor(): BackInterceptorEntry | null {
  'background only';
  return backInterceptors[backInterceptors.length - 1] ?? null;
}

function dispatchBackStackEvent(event: BackEvent): void {
  'background only';
  if (event.phase === 'start' || activeBackInterceptor === null) {
    activeBackInterceptor = topBackInterceptor();
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

function reconcileBackStack(): Promise<void> {
  'background only';
  backStackDesiredEnabled = backInterceptors.length > 0;
  backStackSync = backStackSync
    .catch(() => {})
    .then(async () => {
      'background only';
      while (backStackEnabled !== backStackDesiredEnabled) {
        const nextEnabled = backStackDesiredEnabled;
        await back.setEnabled(nextEnabled);
        backStackEnabled = nextEnabled;
      }
    });
  return backStackSync;
}

/**
 * LIFO dispatcher for nested Lynx UI such as dropdowns, dialogs and sheets.
 * Native interception remains enabled until the final entry is removed.
 */
export const backStack = {
  addInterceptor(listener: BackListener): BackInterceptorRegistration {
    'background only';
    ensureBackStackListener();
    const entry: BackInterceptorEntry = { listener, removed: false };
    backInterceptors.push(entry);
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
