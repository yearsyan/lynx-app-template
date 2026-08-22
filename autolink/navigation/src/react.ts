import { useEffect, useInitData, useRef } from '@lynx-js/react';

import { type BackListener, backStack } from './index.js';

export * from './overlay.js';

// ---------------------------------------------------------------------------
// Route init data
// ---------------------------------------------------------------------------

/** Route metadata injected by native hosts for secondary Lynx pages. */
export interface NativeRouteEnvironment {
  bundle: string;
  presentation: 'push' | 'sheet';
  transparent: boolean;
  statusBarStyle: 'dark-content' | 'light-content';
  animation: 'default' | 'fade' | 'none';
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
