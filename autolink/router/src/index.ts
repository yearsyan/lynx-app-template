import { completeNativeCall, requireNativeModule } from './bridge.generated.js';

export * from './native.generated.js';

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

function requireRouterModule() {
  'background only';
  return requireNativeModule();
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
      requireRouterModule().open(normalized, callback),
    );
  },

  close(): Promise<void> {
    'background only';
    return completeNativeCall((callback) =>
      requireRouterModule().close(callback),
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
      requireRouterModule().openURL(url, callback),
    );
  },
};
