/** Shared contracts and wrappers for native modules provided by each host. */
export * from './nativeEnvironment.js';
export * from './nativeWebSocket.js';

export interface NativeKVModule {
  setString(
    key: string,
    value: string,
    callback: (error: string) => void,
  ): void;
  getString(
    key: string,
    defaultValue: string | null,
    callback: (value: string | null) => void,
  ): void;
  remove(key: string, callback: (error: string) => void): void;
  clear(callback: (error: string) => void): void;
  contains(key: string, callback: (contains: boolean) => void): void;
}

export type NativeRoutePresentation = 'push' | 'modal' | 'sheet';
export type NativeStatusBarStyle = 'dark-content' | 'light-content';

export interface NativeRouteOptions {
  bundle: string;
  presentation?: NativeRoutePresentation;
  transparent?: boolean;
  /** Foreground style for status-bar icons and text on the destination page. */
  statusBarStyle?: NativeStatusBarStyle;
  params?: Record<string, unknown>;
}

export interface NativeRouterModule {
  open(options: NativeRouteOptions, callback: (error: string) => void): void;
  close(callback: (error: string) => void): void;
}

export interface NativeStatusBarModule {
  setStyle(
    style: NativeStatusBarStyle,
    callback: (error: string) => void,
  ): void;
}

export type NativeBackPlatform = 'android' | 'ios' | 'harmony';
export type NativeBackPhase = 'start' | 'progress' | 'cancel' | 'commit';
export type NativeBackSource = 'system' | 'gesture' | 'button';
export type NativeBackEdge = 'left' | 'right' | 'none';

export interface NativeBackEvent {
  platform: NativeBackPlatform;
  phase: NativeBackPhase;
  progress: number;
  source: NativeBackSource;
  edge: NativeBackEdge;
  touchX: number;
  touchY: number;
}

export interface NativeBackModule {
  setEnabled(enabled: boolean, callback: (error: string) => void): void;
}

export type NativeBackListener = (event: NativeBackEvent) => void;

export interface NativeBackInterceptorRegistration {
  /** Resolves after the native host has enabled back interception. */
  readonly ready: Promise<void>;
  /** Removes this interceptor. Calling remove more than once is safe. */
  remove(): void;
}

export const NATIVE_BACK_EVENT = 'nativeBack';

interface TemplateNativeModules {
  NativeKVModule?: NativeKVModule;
  NativeRouterModule?: NativeRouterModule;
  NativeStatusBarModule?: NativeStatusBarModule;
  NativeBackModule?: NativeBackModule;
}

function nativeModules(): TemplateNativeModules {
  'background only';
  return NativeModules as TemplateNativeModules;
}

function requireKVModule(): NativeKVModule {
  'background only';
  const module = nativeModules().NativeKVModule;
  if (module === undefined) {
    throw new Error('NativeKVModule is not registered by the native host');
  }
  return module;
}

function requireRouterModule(): NativeRouterModule {
  'background only';
  const module = nativeModules().NativeRouterModule;
  if (module === undefined) {
    throw new Error('NativeRouterModule is not registered by the native host');
  }
  return module;
}

function requireStatusBarModule(): NativeStatusBarModule {
  'background only';
  const module = nativeModules().NativeStatusBarModule;
  if (module === undefined) {
    throw new Error(
      'NativeStatusBarModule is not registered by the native host',
    );
  }
  return module;
}

function requireBackModule(): NativeBackModule {
  'background only';
  const module = nativeModules().NativeBackModule;
  if (module === undefined) {
    throw new Error('NativeBackModule is not registered by the native host');
  }
  return module;
}

function isNativeBackEvent(value: unknown): value is NativeBackEvent {
  'background only';
  if (typeof value !== 'object' || value === null) {
    return false;
  }
  const event = value as Partial<NativeBackEvent>;
  return (
    (event.platform === 'android' ||
      event.platform === 'ios' ||
      event.platform === 'harmony') &&
    (event.phase === 'start' ||
      event.phase === 'progress' ||
      event.phase === 'cancel' ||
      event.phase === 'commit') &&
    typeof event.progress === 'number' &&
    (event.source === 'system' ||
      event.source === 'gesture' ||
      event.source === 'button') &&
    (event.edge === 'left' ||
      event.edge === 'right' ||
      event.edge === 'none') &&
    typeof event.touchX === 'number' &&
    typeof event.touchY === 'number'
  );
}

function validateKey(key: string): void {
  'background only';
  if (key.trim().length === 0) {
    throw new Error('MMKV key must not be empty');
  }
}

function validateStatusBarStyle(
  style: NativeStatusBarStyle,
): NativeStatusBarStyle {
  'background only';
  if (style !== 'dark-content' && style !== 'light-content') {
    throw new Error(`Invalid status bar style: ${String(style)}`);
  }
  return style;
}

function complete(
  action: (callback: (error: string) => void) => void,
): Promise<void> {
  'background only';
  return new Promise((resolve, reject) => {
    action((error) => {
      if (error.length > 0) {
        reject(new Error(error));
      } else {
        resolve();
      }
    });
  });
}

export const nativeKV = {
  setString(key: string, value: string): Promise<void> {
    'background only';
    validateKey(key);
    return complete((callback) =>
      requireKVModule().setString(key, value, callback),
    );
  },

  getString(
    key: string,
    defaultValue: string | null = null,
  ): Promise<string | null> {
    'background only';
    validateKey(key);
    return new Promise((resolve) => {
      requireKVModule().getString(key, defaultValue, resolve);
    });
  },

  remove(key: string): Promise<void> {
    'background only';
    validateKey(key);
    return complete((callback) => requireKVModule().remove(key, callback));
  },

  clear(): Promise<void> {
    'background only';
    return complete((callback) => requireKVModule().clear(callback));
  },

  contains(key: string): Promise<boolean> {
    'background only';
    validateKey(key);
    return new Promise((resolve) => {
      requireKVModule().contains(key, resolve);
    });
  },

  async setJSON(key: string, value: unknown): Promise<void> {
    'background only';
    await this.setString(key, JSON.stringify(value));
  },

  async getJSON<T>(key: string, defaultValue: T): Promise<T> {
    'background only';
    const serialized = await this.getString(key);
    if (serialized === null) {
      return defaultValue;
    }
    try {
      return JSON.parse(serialized) as T;
    } catch {
      return defaultValue;
    }
  },
};

export const nativeRouter = {
  open(options: NativeRouteOptions): Promise<void> {
    'background only';
    if (!/^[a-z0-9][a-z0-9-]*$/.test(options.bundle)) {
      throw new Error(`Invalid Lynx bundle name: ${options.bundle}`);
    }
    const normalized: NativeRouteOptions = {
      bundle: options.bundle,
      presentation: options.presentation ?? 'push',
      transparent: options.transparent ?? options.presentation === 'sheet',
      statusBarStyle: validateStatusBarStyle(
        options.statusBarStyle ?? 'dark-content',
      ),
      params: options.params ?? {},
    };
    return complete((callback) =>
      requireRouterModule().open(normalized, callback),
    );
  },

  close(): Promise<void> {
    'background only';
    return complete((callback) => requireRouterModule().close(callback));
  },
};

/** Controls the foreground color of the current native status bar. */
export const nativeStatusBar = {
  setStyle(style: NativeStatusBarStyle): Promise<void> {
    'background only';
    const normalized = validateStatusBarStyle(style);
    return complete((callback) =>
      requireStatusBarModule().setStyle(normalized, callback),
    );
  },
};

export const nativeBack = {
  setEnabled(enabled: boolean): Promise<void> {
    'background only';
    return complete((callback) =>
      requireBackModule().setEnabled(enabled, callback),
    );
  },

  addListener(listener: NativeBackListener): () => void {
    'background only';
    const emitter = lynx.getJSModule('GlobalEventEmitter');
    const adapter = (payload: unknown) => {
      'background only';
      if (isNativeBackEvent(payload)) {
        listener(payload);
      }
    };
    emitter.addListener(NATIVE_BACK_EVENT, adapter);
    return () => {
      'background only';
      emitter.removeListener(NATIVE_BACK_EVENT, adapter);
    };
  },
};

interface NativeBackInterceptorEntry {
  listener: NativeBackListener;
  removed: boolean;
}

const nativeBackInterceptors: NativeBackInterceptorEntry[] = [];
let activeNativeBackInterceptor: NativeBackInterceptorEntry | null = null;
let removeNativeBackStackListener: (() => void) | null = null;
let nativeBackStackEnabled = false;
let nativeBackStackDesiredEnabled = false;
let nativeBackStackSync: Promise<void> = Promise.resolve();

function topNativeBackInterceptor(): NativeBackInterceptorEntry | null {
  'background only';
  return nativeBackInterceptors[nativeBackInterceptors.length - 1] ?? null;
}

function dispatchNativeBackStackEvent(event: NativeBackEvent): void {
  'background only';
  if (event.phase === 'start' || activeNativeBackInterceptor === null) {
    activeNativeBackInterceptor = topNativeBackInterceptor();
  }

  const target = activeNativeBackInterceptor;
  const isTerminal = event.phase === 'cancel' || event.phase === 'commit';
  try {
    // Keep a gesture pinned to the interceptor that received `start`. If that
    // popup disappears mid-gesture, never leak the remaining phases to the
    // popup underneath it.
    if (target !== null && !target.removed) {
      target.listener(event);
    }
  } finally {
    if (isTerminal) {
      activeNativeBackInterceptor = null;
    }
  }
}

function ensureNativeBackStackListener(): void {
  'background only';
  if (removeNativeBackStackListener !== null) {
    return;
  }
  removeNativeBackStackListener = nativeBack.addListener(
    dispatchNativeBackStackEvent,
  );
}

function reportNativeBackStackError(error: unknown): void {
  'background only';
  const message = error instanceof Error ? error.message : String(error);
  console.error(`Unable to synchronize native back stack: ${message}`);
}

function reconcileNativeBackStack(): Promise<void> {
  'background only';
  nativeBackStackDesiredEnabled = nativeBackInterceptors.length > 0;
  nativeBackStackSync = nativeBackStackSync
    .catch(() => {})
    .then(async () => {
      'background only';
      while (nativeBackStackEnabled !== nativeBackStackDesiredEnabled) {
        const nextEnabled = nativeBackStackDesiredEnabled;
        await nativeBack.setEnabled(nextEnabled);
        nativeBackStackEnabled = nextEnabled;
      }
    });
  return nativeBackStackSync;
}

/**
 * LIFO back dispatcher for nested Lynx UI such as dropdowns, dialogs and
 * sheets. Only the most recently added interceptor receives a gesture. Native
 * interception stays enabled until the final entry is removed.
 */
export const nativeBackStack = {
  addInterceptor(
    listener: NativeBackListener,
  ): NativeBackInterceptorRegistration {
    'background only';
    ensureNativeBackStackListener();
    const entry: NativeBackInterceptorEntry = { listener, removed: false };
    nativeBackInterceptors.push(entry);
    const ready = reconcileNativeBackStack();
    ready.catch(reportNativeBackStackError);

    return {
      ready,
      remove(): void {
        'background only';
        if (entry.removed) {
          return;
        }
        entry.removed = true;
        const index = nativeBackInterceptors.lastIndexOf(entry);
        if (index >= 0) {
          nativeBackInterceptors.splice(index, 1);
        }
        reconcileNativeBackStack().catch(reportNativeBackStackError);
      },
    };
  },

  get size(): number {
    'background only';
    return nativeBackInterceptors.length;
  },
};
