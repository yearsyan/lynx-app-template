import { UIContext } from '@kit.ArkUI';
import { LynxContext, LynxModule, LynxViewClient } from '@lynx/lynx';

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
export const ROUTE_HANDLER_CONTEXT_DATA_KEY: string =
  '@lynx-template/autolink-navigation/route-handler';

/** Stable key through which the declarative host supplies its Back route session. */
export const BACK_REGISTRATION_CONTEXT_DATA_KEY: string =
  '@lynx-template/autolink-navigation/back-registration';

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

class NativeBackEventPayload {
  platform: string = 'harmony';
  phase: string;
  progress: number;
  source: string = 'system';
  edge: string = 'none';
  touchX: number = 0;
  touchY: number = 0;
  interceptorId: string;
  gestureId: number;

  constructor(
    phase: string,
    progress: number,
    interceptorId: string,
    gestureId: number,
  ) {
    this.phase = phase;
    this.progress = progress;
    this.interceptorId = interceptorId;
    this.gestureId = gestureId;
  }
}

class NativeBackSession {
  private enabled: boolean = false;
  private context: LynxContext | undefined = undefined;
  private interceptorId: string = '';
  private targetId: string = '';
  private revision: number = 0;
  private nextGestureId: number = 0;

  setEnabled(context: LynxContext, enabled: boolean): void {
    this.revision += 1;
    this.interceptorId = '';
    this.targetId = '';
    this.context = enabled ? context : undefined;
    this.enabled = enabled;
  }

  configure(
    context: LynxContext,
    enabled: boolean,
    interceptorId: string,
    targetId: string,
    revision: number,
  ): void {
    if (revision < this.revision) {
      return;
    }
    this.revision = revision;
    this.interceptorId = interceptorId;
    this.targetId = targetId;
    this.context = enabled ? context : undefined;
    this.enabled = enabled;
  }

  detach(context: LynxContext): void {
    if (this.context === context) {
      this.destroy();
    }
  }

  handleBack(): boolean {
    const context = this.context;
    if (!this.enabled || context === undefined) {
      return false;
    }
    const gestureId = ++this.nextGestureId;
    context.sendGlobalEvent('back', [
      new NativeBackEventPayload('start', 0, this.interceptorId, gestureId),
    ]);
    context.sendGlobalEvent('back', [
      new NativeBackEventPayload('commit', 1, this.interceptorId, gestureId),
    ]);
    return true;
  }

  destroy(): void {
    this.enabled = false;
    this.context = undefined;
  }
}

/**
 * Package-owned route stack used by the host's synchronous onBackPress event.
 * HarmonyOS has no public progress callback, so enabled sessions emit only a
 * discrete start and commit pair.
 */
export class NativeBackController {
  private readonly sessions: Map<string, NativeBackSession> = new Map();
  private readonly activeRouteIDs: string[] = [];
  private uiContext: UIContext | undefined = undefined;

  attach(uiContext: UIContext): void {
    this.uiContext = uiContext;
  }

  activate(routeID: string): void {
    if (!this.sessions.has(routeID)) {
      this.sessions.set(routeID, new NativeBackSession());
    }
    const existingIndex = this.activeRouteIDs.indexOf(routeID);
    if (existingIndex >= 0) {
      this.activeRouteIDs.splice(existingIndex, 1);
    }
    this.activeRouteIDs.push(routeID);
  }

  deactivate(routeID: string): void {
    this.sessions.get(routeID)?.destroy();
    this.sessions.delete(routeID);
    const index = this.activeRouteIDs.indexOf(routeID);
    if (index >= 0) {
      this.activeRouteIDs.splice(index, 1);
    }
  }

  setEnabled(
    routeID: string,
    context: LynxContext,
    enabled: boolean,
    callback: (error: string) => void,
  ): void {
    this.runOnUI(() => {
      const session = this.sessions.get(routeID);
      if (session === undefined) {
        callback('Native Back page is not active');
        return;
      }
      session.setEnabled(context, enabled);
      callback('');
    });
  }

  configure(
    routeID: string,
    context: LynxContext,
    enabled: boolean,
    interceptorId: string,
    targetId: string,
    revision: number,
    callback: (error: string) => void,
  ): void {
    this.runOnUI(() => {
      const session = this.sessions.get(routeID);
      if (session === undefined) {
        callback('Native Back page is not active');
        return;
      }
      session.configure(context, enabled, interceptorId, targetId, revision);
      callback('');
    });
  }

  detach(routeID: string, context: LynxContext): void {
    this.runOnUI(() => {
      this.sessions.get(routeID)?.detach(context);
    });
  }

  handleBack(): boolean {
    const routeID = this.activeRouteIDs[this.activeRouteIDs.length - 1];
    if (routeID === undefined) {
      return false;
    }
    return this.sessions.get(routeID)?.handleBack() ?? false;
  }

  private runOnUI(task: () => void): void {
    if (this.uiContext === undefined) {
      task();
      return;
    }
    this.uiContext.runScopedTask(task);
  }
}

/** Route-scoped adapter installed into LynxContext.contextData by the host. */
export class BackRegistration {
  readonly controller: NativeBackController;
  readonly routeID: string;

  constructor(controller: NativeBackController, routeID: string) {
    this.controller = controller;
    this.routeID = routeID;
  }

  setEnabled(
    context: LynxContext,
    enabled: boolean,
    callback: (error: string) => void,
  ): void {
    this.controller.setEnabled(this.routeID, context, enabled, callback);
  }

  configure(
    context: LynxContext,
    enabled: boolean,
    interceptorId: string,
    targetId: string,
    revision: number,
    callback: (error: string) => void,
  ): void {
    this.controller.configure(
      this.routeID,
      context,
      enabled,
      interceptorId,
      targetId,
      revision,
      callback,
    );
  }

  detach(context: LynxContext): void {
    this.controller.detach(this.routeID, context);
  }
}

function registrationFor(context: LynxContext): BackRegistration | undefined {
  const contextData = context.getContextData();
  return contextData?.[BACK_REGISTRATION_CONTEXT_DATA_KEY] as BackRegistration | undefined;
}

class BackLifecycleClient extends LynxViewClient {
  private readonly context: LynxContext;

  constructor(context: LynxContext) {
    super();
    this.context = context;
  }

  override onDestroy(): void {
    registrationFor(this.context)?.detach(this.context);
  }
}

/**
 * Route navigation and Back interception exported to Lynx as Navigation.
 * open/close/openURL follow the host navigation policy; setEnabled/configure
 * drive the host's synchronous Back route session.
 */
export class NavigationModule extends LynxModule {
  static readonly NAME: string = 'Navigation';

  constructor(context: LynxContext, param?: Object) {
    super(context, param);
    context.getLynxViewClient()?.push(new BackLifecycleClient(context));
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
    const handler = this.routeHandler();
    if (handler === undefined) {
      callback('Native navigation has no route handler host');
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
    const handler = this.routeHandler();
    if (handler === undefined) {
      callback('Native navigation has no route handler host');
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
    const handler = this.routeHandler();
    if (handler === undefined) {
      callback('Native navigation has no route handler host');
      return;
    }
    handler.openURL(url, callback);
  }

  setEnabled(enabled: boolean, callback: (error: string) => void): void {
    const registration = registrationFor(this.context);
    if (registration === undefined) {
      callback('Native Back has no Navigation host');
      return;
    }
    registration.setEnabled(this.context, enabled, callback);
  }

  configure(
    enabled: boolean,
    interceptorId: string,
    targetId: string,
    revision: number,
    callback: (error: string) => void,
  ): void {
    const registration = registrationFor(this.context);
    if (registration === undefined) {
      callback('Native Back has no Navigation host');
      return;
    }
    // HarmonyOS exposes no Back progress. targetId is intentionally accepted
    // for protocol parity while commit remains a discrete JS state update.
    registration.configure(
      this.context,
      enabled,
      interceptorId,
      targetId,
      revision,
      callback,
    );
  }

  private routeHandler(): NativeRouterHandler | undefined {
    const contextData = this.context.getContextData();
    return contextData?.[ROUTE_HANDLER_CONTEXT_DATA_KEY] as NativeRouterHandler | undefined;
  }
}
