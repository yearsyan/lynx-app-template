import { useInitData } from '@lynx-js/react';

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
