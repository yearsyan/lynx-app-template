import { useInitData } from '@lynx-js/react';

import type {
  RouteAnimation,
  RoutePresentation,
  StatusBarStyle,
} from './index.js';

/** Route metadata injected by native hosts for secondary Lynx pages. */
export interface NativeRouteEnvironment {
  bundle: string;
  presentation: RoutePresentation;
  transparent: boolean;
  statusBarStyle: StatusBarStyle;
  animation: RouteAnimation;
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
