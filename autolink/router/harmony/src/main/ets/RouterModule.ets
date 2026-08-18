import { LynxContext, LynxModule } from '@lynx/lynx';

export interface NativeRouteOptions {
  bundle: string;
  presentation?: string;
  transparent?: boolean;
  statusBarStyle?: string;
  animation?: string;
  params?: Record<string, Object>;
}

/** Host navigation policy installed in LynxContext.contextData by the app. */
export interface NativeRouterHandler {
  open(options: NativeRouteOptions, callback: (error: string) => void): void;
  close(callback: (error: string) => void): void;
  openURL(url: string, callback: (error: string) => void): void;
}

/** Stable contextData key shared with HarmonyOS hosts that provide navigation. */
export const ROUTER_CONTEXT_DATA_KEY: string =
  '@lynx-template/autolink-router/route-handler';

const ROUTE_ANIMATION_DEFAULT: string = 'default';
const ROUTE_ANIMATION_FADE: string = 'fade';
const ROUTE_ANIMATION_NONE: string = 'none';
const STATUS_BAR_STYLE_DARK_CONTENT: string = 'dark-content';
const STATUS_BAR_STYLE_LIGHT_CONTENT: string = 'light-content';

function isRouteAnimation(value: string): boolean {
  return value === ROUTE_ANIMATION_DEFAULT ||
    value === ROUTE_ANIMATION_FADE ||
    value === ROUTE_ANIMATION_NONE;
}

function isStatusBarStyle(value: string): boolean {
  return value === STATUS_BAR_STYLE_DARK_CONTENT ||
    value === STATUS_BAR_STYLE_LIGHT_CONTENT;
}

/** Opens Lynx bundles and system URLs through the host navigation policy. */
export class RouterModule extends LynxModule {
  static readonly NAME: string = 'Router';

  constructor(context: LynxContext, param?: Object) {
    super(context, param);
  }

  open(options: NativeRouteOptions, callback: (error: string) => void): void {
    if (options === undefined || typeof options.bundle !== 'string' ||
      !new RegExp('^[a-z0-9][a-z0-9-]*$').test(options.bundle)) {
      callback(`Invalid Lynx bundle name: ${options?.bundle ?? ''}`);
      return;
    }
    const animation = options.animation ?? ROUTE_ANIMATION_DEFAULT;
    if (!isRouteAnimation(animation)) {
      callback(`Invalid route animation: ${animation}`);
      return;
    }
    const statusBarStyle = options.statusBarStyle ?? STATUS_BAR_STYLE_DARK_CONTENT;
    if (!isStatusBarStyle(statusBarStyle)) {
      callback(`Invalid status bar style: ${statusBarStyle}`);
      return;
    }
    const presentation = options.presentation ?? 'push';
    const handler = this.handler();
    if (handler === undefined) {
      callback('Native router has no Navigation host');
      return;
    }
    handler.open({
      bundle: options.bundle,
      presentation,
      transparent: options.transparent ?? presentation === 'sheet',
      statusBarStyle,
      animation,
      params: options.params ?? {},
    }, callback);
  }

  close(callback: (error: string) => void): void {
    const handler = this.handler();
    if (handler === undefined) {
      callback('Native router has no Navigation host');
      return;
    }
    handler.close(callback);
  }

  openURL(url: string, callback: (error: string) => void): void {
    if (url.trim().length === 0 || url !== url.trim() ||
      !new RegExp('^[a-zA-Z][a-zA-Z0-9+.-]*:').test(url)) {
      callback(`Invalid URL: ${url}`);
      return;
    }
    const handler = this.handler();
    if (handler === undefined) {
      callback('Native router has no Navigation host');
      return;
    }
    handler.openURL(url, callback);
  }

  private handler(): NativeRouterHandler | undefined {
    const contextData = this.context.getContextData();
    return contextData?.[ROUTER_CONTEXT_DATA_KEY] as NativeRouterHandler | undefined;
  }
}
