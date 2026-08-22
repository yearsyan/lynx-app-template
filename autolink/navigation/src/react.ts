import { useEffect, useInitData, useRef } from '@lynx-js/react';

import { type BackListener, backStack } from './index.js';

export * from './overlay.js';

// ---------------------------------------------------------------------------
// Route init data
// ---------------------------------------------------------------------------

/** Route metadata injected by native hosts for secondary Lynx pages. */
export interface NativeRouteEnvironment {
  bundle: string;
  statusBarStyle: 'dark-content' | 'light-content';
  animation: 'default' | 'fade' | 'none' | 'present';
  params: Record<string, unknown>;
}

declare module '@lynx-js/react' {
  interface InitData {
    route?: NativeRouteEnvironment;
  }
}

/** Typed view of the current native route's params init data. */
export function useRouteParams<
  T extends Record<string, unknown> = Record<string, unknown>,
>(): Partial<T> {
  const initData = useInitData();
  return (initData?.route?.params ?? {}) as Partial<T>;
}

// ---------------------------------------------------------------------------
// Back interception
// ---------------------------------------------------------------------------

/**
 * Registers a native Back interceptor while enabled. Interceptors are LIFO;
 * the top interceptor must handle commit by closing its UI or route.
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

/**
 * Turns one system Back commit into a dismissal while enabled. Intended for
 * single-dismiss surfaces assembled from JS UI (dialog, drawer, filter
 * panel): Back closes the surface instead of the route. A cancelled gesture
 * leaves the surface open, and the registration is removed when the surface
 * unmounts or closes, so the next Back returns to normal navigation.
 */
export function useBackDismissal(onDismiss: () => void, enabled = true): void {
  const handlerRef = useRef(onDismiss);
  useEffect(() => {
    handlerRef.current = onDismiss;
  });
  useEffect(() => {
    if (!enabled) {
      return;
    }
    const registration = backStack.addInterceptor((event) => {
      'background only';
      if (event.phase === 'commit') {
        handlerRef.current();
      }
    });
    return registration.remove;
  }, [enabled]);
}
