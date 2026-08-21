import { useEffect, useRef } from '@lynx-js/react';

import { type BackListener, backStack } from './index.js';

export * from './overlay.js';

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
