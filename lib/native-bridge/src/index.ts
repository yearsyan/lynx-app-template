/** Shared contracts and wrappers for native modules provided by each host. */
import { useEffect, useInitData, useRef } from '@lynx-js/react';
import type { PickerModule, PickerOptions } from './fileSystem.js';
import { completePicker, normalizePickerOptions } from './fileSystem.js';

export * from './biometric.js';
export * from './deviceInfo.js';
export * from './display.js';
export * from './fileSystem.js';
export * from './nativeEnvironment.js';
export * from './screenshot.js';
export * from './toast.js';
export * from './webSocket.js';

export interface KVModule {
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

export type RoutePresentation = 'push' | 'sheet';
export type RouteAnimation = 'default' | 'fade' | 'none';
export type StatusBarStyle = 'dark-content' | 'light-content';

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

export interface RouterModule {
  open(options: RouteOptions, callback: (error: string) => void): void;
  close(callback: (error: string) => void): void;
  /**
   * Resolves the URL through the system, launching the app that registered
   * the scheme — including this app's own pages.
   */
  openURL(url: string, callback: (error: string) => void): void;
}

export interface StatusBarModule {
  setStyle(style: StatusBarStyle, callback: (error: string) => void): void;
}

export interface ClipboardModule {
  setString(text: string, callback: (error: string) => void): void;
  getString(callback: (text: string | null) => void): void;
}

export type HapticImpact = 'light' | 'medium' | 'heavy';

export interface HapticsModule {
  impact(style: HapticImpact, callback: (error: string) => void): void;
}

/** Album utilities: picking images and saving images into the system album. */
export interface AlbumUtilsModule {
  pick(maxSelection: number, callback: (resultJSON: string) => void): void;
  saveToAlbum(uri: string, callback: (error: string) => void): void;
}

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

export interface BackModule {
  setEnabled(enabled: boolean, callback: (error: string) => void): void;
}

export type BackListener = (event: BackEvent) => void;

export interface BackInterceptorRegistration {
  /** Resolves after the native host has enabled back interception. */
  readonly ready: Promise<void>;
  /** Removes this interceptor. Calling remove more than once is safe. */
  remove(): void;
}

export const BACK_EVENT = 'back';

interface AppModules {
  KV?: KVModule;
  Router?: RouterModule;
  StatusBar?: StatusBarModule;
  Back?: BackModule;
  Clipboard?: ClipboardModule;
  Haptics?: HapticsModule;
  AlbumUtils?: AlbumUtilsModule;
}

function modules(): AppModules {
  'background only';
  return NativeModules as AppModules;
}

function requireKVModule(): KVModule {
  'background only';
  const module = modules().KV;
  if (module === undefined) {
    throw new Error('KV is not registered by the host');
  }
  return module;
}

function requireRouterModule(): RouterModule {
  'background only';
  const module = modules().Router;
  if (module === undefined) {
    throw new Error('Router is not registered by the host');
  }
  return module;
}

function requireStatusBarModule(): StatusBarModule {
  'background only';
  const module = modules().StatusBar;
  if (module === undefined) {
    throw new Error('StatusBar is not registered by the host');
  }
  return module;
}

function requireClipboardModule(): ClipboardModule {
  'background only';
  const module = modules().Clipboard;
  if (module === undefined) {
    throw new Error('Clipboard is not registered by the host');
  }
  return module;
}

function requireHapticsModule(): HapticsModule {
  'background only';
  const module = modules().Haptics;
  if (module === undefined) {
    throw new Error('Haptics is not registered by the host');
  }
  return module;
}

function requireAlbumUtilsModule(): AlbumUtilsModule {
  'background only';
  const module = modules().AlbumUtils;
  if (module === undefined) {
    throw new Error('AlbumUtils is not registered by the host');
  }
  return module;
}

function requireBackModule(): BackModule {
  'background only';
  const module = modules().Back;
  if (module === undefined) {
    throw new Error('Back is not registered by the host');
  }
  return module;
}

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

function validateStatusBarStyle(style: StatusBarStyle): StatusBarStyle {
  'background only';
  if (style !== 'dark-content' && style !== 'light-content') {
    throw new Error(`Invalid status bar style: ${String(style)}`);
  }
  return style;
}

function validateRouteAnimation(animation: RouteAnimation): RouteAnimation {
  'background only';
  if (animation !== 'default' && animation !== 'fade' && animation !== 'none') {
    throw new Error(`Invalid route animation: ${String(animation)}`);
  }
  return animation;
}

function validateHapticImpact(style: HapticImpact): HapticImpact {
  'background only';
  if (style !== 'light' && style !== 'medium' && style !== 'heavy') {
    throw new Error(`Invalid haptic impact style: ${String(style)}`);
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

export const kv = {
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

export const router = {
  open(options: RouteOptions): Promise<void> {
    'background only';
    const normalized: RouteOptions = {
      bundle: options.bundle,
      presentation: options.presentation ?? 'push',
      transparent: options.transparent ?? options.presentation === 'sheet',
      statusBarStyle: validateStatusBarStyle(
        options.statusBarStyle ?? 'dark-content',
      ),
      animation: validateRouteAnimation(options.animation ?? 'default'),
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

  /**
   * Opens a URL through the system router. Any app that registered the
   * scheme can handle it, including this app's own scheme pages —
   * `lynxapp://main`, `weixin://`, `imeituan://`, `https://…` and so on.
   */
  openURL(url: string): Promise<void> {
    'background only';
    return complete((callback) => requireRouterModule().openURL(url, callback));
  },
};

/** Controls the foreground color of the current native status bar. */
export const statusBar = {
  setStyle(style: StatusBarStyle): Promise<void> {
    'background only';
    const normalized = validateStatusBarStyle(style);
    return complete((callback) =>
      requireStatusBarModule().setStyle(normalized, callback),
    );
  },
};

/** System clipboard for plain text. */
export const clipboard = {
  setString(text: string): Promise<void> {
    'background only';
    return complete((callback) =>
      requireClipboardModule().setString(text, callback),
    );
  },

  getString(): Promise<string | null> {
    'background only';
    return new Promise((resolve) => {
      requireClipboardModule().getString((text) => {
        'background only';
        resolve(typeof text === 'string' ? text : null);
      });
    });
  },
};

/** One-shot haptic feedback. */
export const haptics = {
  impact(style: HapticImpact): Promise<void> {
    'background only';
    const normalized = validateHapticImpact(style);
    return complete((callback) =>
      requireHapticsModule().impact(normalized, callback),
    );
  },
};

/** Picks images from the system album and saves image URIs back into it. */
export const albumUtils = {
  /** Selects images through the platform's user-visible album picker. */
  pick(options: PickerOptions = {}): Promise<string[]> {
    'background only';
    const maxSelection = normalizePickerOptions(options);
    return completePicker(
      requireAlbumUtilsModule() as PickerModule,
      maxSelection,
    );
  },

  /**
   * Writes an image URI (a picker or cache URI readable by `fileSystem`)
   * into the system album. The platform may ask the user for confirmation.
   */
  saveToAlbum(uri: string): Promise<void> {
    'background only';
    const normalized = uri.trim();
    if (normalized.length === 0) {
      throw new Error('Image URI must not be empty');
    }
    return complete((callback) =>
      requireAlbumUtilsModule().saveToAlbum(normalized, callback),
    );
  },
};

export const back = {
  setEnabled(enabled: boolean): Promise<void> {
    'background only';
    return complete((callback) =>
      requireBackModule().setEnabled(enabled, callback),
    );
  },

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
    // Keep a gesture pinned to the interceptor that received `start`. If that
    // popup disappears mid-gesture, never leak the remaining phases to the
    // popup underneath it.
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
  if (removeBackStackListener !== null) {
    return;
  }
  removeBackStackListener = back.addListener(dispatchBackStackEvent);
}

function reportBackStackError(error: unknown): void {
  'background only';
  const message = error instanceof Error ? error.message : String(error);
  console.error(`Unable to synchronize native back stack: ${message}`);
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
 * LIFO back dispatcher for nested Lynx UI such as dropdowns, dialogs and
 * sheets. Only the most recently added interceptor receives a gesture. Native
 * interception stays enabled until the final entry is removed.
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

/**
 * Typed view of the current route's `params` init data. Values keep their
 * transport types, so validate them before use.
 */
export function useRouteParams<
  T extends Record<string, unknown> = Record<string, unknown>,
>(): Partial<T> {
  const initData = useInitData();
  return (initData?.route?.params ?? {}) as Partial<T>;
}

/**
 * Registers a native-back interceptor while `enabled` and removes it on
 * cleanup. Interceptors form a LIFO stack, so the most recently enabled one
 * sees the gesture first. The latest `onEvent` is always invoked; only
 * `enabled` re-registers. The top interceptor must handle `commit` (close
 * its popup or call `router.close()`), or the back gesture is
 * consumed with no visible effect.
 */
export function useBackInterceptor(
  onEvent: BackListener,
  enabled = true,
): void {
  const handlerRef = useRef<BackListener>(onEvent);
  useEffect(() => {
    handlerRef.current = onEvent;
  });
  useEffect(() => {
    if (!enabled) {
      return;
    }
    const registration = backStack.addInterceptor((event) => {
      'background only';
      handlerRef.current(event);
    });
    return registration.remove;
  }, [enabled]);
}
