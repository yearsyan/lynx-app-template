import { common } from '@kit.AbilityKit';
import { UIContext, window } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';

import { BundleConfig } from '../config/BundleConfig';
import { STATUS_BAR_STYLE_DARK_CONTENT } from '@lynx-template/autolink-device';
import { NativeRouteResult } from '@lynx-template/autolink-navigation';

interface NativeRouteOptions {
  bundle: string;
  statusBarStyle?: string;
  animation?: string;
  presentation?: string;
  overlay?: NativeRoutePresentOptions;
  params?: Record<string, Object>;
}

interface NativeRoutePresentOptions {
  scrimColor?: string;
  backdropTransition?: boolean;
  enter?: NativeRoutePresentContentAnimationOptions;
  exit?: NativeRoutePresentContentAnimationOptions;
  contentTransition?: boolean;
  backdropBlur?: boolean;
  iosSwipeDown?: boolean;
  androidPredictiveBackDown?: boolean;
  dragDownToDismiss?: boolean;
}

interface NativeRoutePresentContentAnimationOptions {
  opacity?: boolean;
  push?: boolean;
}

const ROUTE_ANIMATION_DEFAULT: string = 'default';
const ROUTE_ANIMATION_FADE: string = 'fade';
const ROUTE_ANIMATION_NONE: string = 'none';
export const ROUTE_PRESENTATION_PAGE: string = 'page';
export const ROUTE_PRESENTATION_INPUT_DIALOG: string = 'inputDialog';
export const ROUTE_PRESENTATION_OVERLAY: string = 'overlay';
/** Blurred backdrops give up pixel alignment, so they capture small. */
const BLURRED_CAPTURE_SCALE: number = 1 / 3;

function routeResultErrorEnvelope(message: string): string {
  const envelope: Record<string, Object> = { 'error': message };
  return JSON.stringify(envelope);
}

/** A pending openForResult callback, resolved when the opened route dies. */
class PendingRouteResult {
  private result: Record<string, Object> | undefined = undefined;
  private readonly onResult: (resultJSON: string) => void;

  constructor(onResult: (resultJSON: string) => void) {
    this.onResult = onResult;
  }

  setResult(result: Record<string, Object>): void {
    this.result = result;
  }

  deliver(): void {
    const envelope: Record<string, Object> =
      this.result === undefined ? {} : { 'value': this.result };
    this.onResult(JSON.stringify(envelope));
  }
}

/**
 * Maps the shared route animation to the ArkUI navigation transition. Overlay
 * routes open with no system animation (their normalized animation is 'none');
 * the page itself layers the previous page's snapshot (see NativeRoute.snapshot)
 * and plays the iOS-like present choreography from the content's first screen.
 */
export function nativeRouteTransitionType(animation: string): NavigationSystemTransitionType {
  if (animation === ROUTE_ANIMATION_FADE) {
    return NavigationSystemTransitionType.FADE;
  }
  if (animation === ROUTE_ANIMATION_NONE) {
    return NavigationSystemTransitionType.NONE;
  }
  return NavigationSystemTransitionType.DEFAULT;
}

export class NativeRoute {
  private static nextNativeBackID: number = 0;
  bundle: string;
  statusBarStyle: string;
  animation: string;
  presentation: string;
  params: Record<string, Object>;
  /** Overlay routes only: snapshot of the previous page shown as the backdrop. */
  snapshot?: image.PixelMap;
  /** Overlay routes only: scrim color ('#AARRGGBB') over the snapshot backdrop. */
  presentScrimColor?: string;
  /** Overlay routes only: snapshot shrink choreography and its reverse on close. */
  presentBackdropTransition: boolean = true;
  /** Overlay routes only: content entering opacity choreography. */
  presentEnterOpacity: boolean = false;
  /** Overlay routes only: content entering full-viewport push choreography. */
  presentEnterPush: boolean = true;
  /** Overlay routes only: content exiting opacity choreography. */
  presentExitOpacity: boolean = false;
  /** Overlay routes only: content exiting full-viewport push choreography. */
  presentExitPush: boolean = true;
  /** Overlay routes only: blur the snapshot (captured at reduced resolution). */
  presentBackdropBlur: boolean = false;
  /** Overlay routes only: let an unclaimed downward pan dismiss interactively. */
  presentDragDownToDismiss: boolean = false;
  /** openForResult routes only: correlates this route with its opener. */
  resultToken?: string;
  readonly nativeBackID: string;

  constructor(
    bundle: string,
    statusBarStyle: string = STATUS_BAR_STYLE_DARK_CONTENT,
    animation: string = ROUTE_ANIMATION_DEFAULT,
    presentation: string = ROUTE_PRESENTATION_PAGE,
    params: Record<string, Object> = {},
    snapshot?: image.PixelMap,
  ) {
    this.bundle = bundle;
    this.statusBarStyle = statusBarStyle;
    this.animation = animation;
    this.presentation = presentation;
    this.params = params;
    this.snapshot = snapshot;
    this.nativeBackID = `native-back-${NativeRoute.nextNativeBackID}`;
    NativeRoute.nextNativeBackID += 1;
  }

  static main(): NativeRoute {
    return new NativeRoute('main');
  }

  bundleURL(): string {
    return `${BundleConfig.EMBEDDED_BUNDLE_DIRECTORY}/${this.bundle}.lynx.bundle`;
  }
}

/** Implements the app-specific ArkUI navigation policy used by NavigationModule. */
export class NativeRouterController {
  static readonly DESTINATION_NAME: string = 'lynx-bundle';

  private static nextResultToken: number = 0;

  private readonly pathStack: NavPathStack;
  private uiContext: UIContext | undefined = undefined;
  private abilityContext: common.UIAbilityContext | undefined = undefined;
  private activeDialogRoute: NativeRoute | undefined = undefined;
  private dialogOpenHandler:
    ((route: NativeRoute, callback: (error: string) => void) => void) | undefined = undefined;
  private dialogCloseHandler:
    ((callback: (error: string) => void) => void) | undefined = undefined;
  // Present routes register their reverse choreography so close() and system
  // Back pop only after the snapshot backdrop has restored the previous page.
  private readonly presentDismissers: Map<string, () => void> = new Map();
  // openForResult routes only: their opener's pending result callback.
  private readonly pendingResults: Map<string, PendingRouteResult> = new Map();

  constructor(pathStack: NavPathStack) {
    this.pathStack = pathStack;
  }

  attach(uiContext: UIContext): void {
    this.uiContext = uiContext;
  }

  attachAbility(context: common.UIAbilityContext): void {
    this.abilityContext = context;
  }

  attachDialogHost(
    open: (route: NativeRoute, callback: (error: string) => void) => void,
    close: (callback: (error: string) => void) => void,
  ): void {
    this.dialogOpenHandler = open;
    this.dialogCloseHandler = close;
  }

  registerPresentDismiss(routeID: string, dismiss: (() => void) | undefined): void {
    if (dismiss === undefined) {
      this.presentDismissers.delete(routeID);
    } else {
      this.presentDismissers.set(routeID, dismiss);
    }
  }

  presentDismissFor(routeID: string): (() => void) | undefined {
    return this.presentDismissers.get(routeID);
  }

  open(options: NativeRouteOptions, callback: (error: string) => void): void {
    this.openInternal(options, undefined, callback);
  }

  openForResult(
    options: NativeRouteOptions,
    onResult: (resultJSON: string) => void,
  ): void {
    NativeRouterController.nextResultToken += 1;
    const token = `route-result-${NativeRouterController.nextResultToken}`;
    this.pendingResults.set(token, new PendingRouteResult(onResult));
    this.openInternal(options, token, (error: string) => {
      // Push failures reject the awaiting promise; a successful push keeps
      // the entry pending until the route disappears.
      if (error.length > 0) {
        this.pendingResults.delete(token);
        onResult(routeResultErrorEnvelope(error));
      }
    });
  }

  close(callback: (error: string) => void): void {
    this.runOnUI(() => {
      this.performClose(callback);
    });
  }

  closeWithResult(
    result: NativeRouteResult,
    callback: (error: string) => void,
  ): void {
    this.runOnUI(() => {
      const dialogRoute = this.activeDialogRoute;
      if (dialogRoute?.resultToken !== undefined) {
        this.pendingResults.get(dialogRoute.resultToken)?.setResult(result);
      } else if (this.pathStack.size() > 0) {
        const top =
          this.pathStack.getParamByIndex(this.pathStack.size() - 1) as NativeRoute | undefined;
        if (top?.resultToken !== undefined) {
          this.pendingResults.get(top.resultToken)?.setResult(result);
        }
      }
      this.performClose(callback);
    });
  }

  /**
   * Resolves the route's pending openForResult entry (with its recorded
   * result, or the no-result envelope) when the route leaves the stack.
   */
  completeRouteResult(route: NativeRoute): void {
    const token = route.resultToken;
    this.runOnUI(() => {
      if (this.activeDialogRoute === route) {
        this.activeDialogRoute = undefined;
      }
      if (token === undefined) {
        return;
      }
      const pending = this.pendingResults.get(token);
      if (pending === undefined) {
        return;
      }
      this.pendingResults.delete(token);
      pending.deliver();
    });
  }

  openURL(url: string, callback: (error: string) => void): void {
    if (this.abilityContext === undefined) {
      callback('Native router has no ability context');
      return;
    }
    this.abilityContext.openLink(url)
      .then(() => callback(''))
      .catch((error: Error) => callback(`Unable to open URL: ${error.message}`));
  }

  /** Pops with no system transition after a present route's reverse choreography. */
  popAfterPresentDismiss(): void {
    this.runOnUI((): void => {
      this.pathStack.pop(false);
    });
  }

  private openInternal(
    options: NativeRouteOptions,
    resultToken: string | undefined,
    onPushFinished: (error: string) => void,
  ): void {
    if (this.activeDialogRoute !== undefined) {
      onPushFinished('An inputDialog route is already open');
      return;
    }
    const presentation = options.presentation ?? ROUTE_PRESENTATION_PAGE;
    if (
      presentation !== ROUTE_PRESENTATION_PAGE &&
      presentation !== ROUTE_PRESENTATION_INPUT_DIALOG &&
      presentation !== ROUTE_PRESENTATION_OVERLAY
    ) {
      onPushFinished(`Invalid route presentation: ${presentation}`);
      return;
    }
    // Overlay routes own their open/close choreography, so they always run
    // without a system transition regardless of the animation value.
    const animation = presentation === ROUTE_PRESENTATION_OVERLAY
      ? ROUTE_ANIMATION_NONE
      : options.animation ??
        (presentation === ROUTE_PRESENTATION_INPUT_DIALOG
          ? ROUTE_ANIMATION_NONE
          : ROUTE_ANIMATION_DEFAULT);
    const route = new NativeRoute(
      options.bundle,
      options.statusBarStyle ?? STATUS_BAR_STYLE_DARK_CONTENT,
      animation,
      presentation,
      options.params ?? {},
    );
    route.presentScrimColor = options.overlay?.scrimColor;
    route.presentBackdropTransition = options.overlay?.backdropTransition ?? true;
    const legacyContentTransition = options.overlay?.contentTransition ?? true;
    route.presentEnterOpacity = options.overlay?.enter?.opacity ?? false;
    route.presentEnterPush = options.overlay?.enter?.push ?? legacyContentTransition;
    route.presentExitOpacity = options.overlay?.exit?.opacity ?? false;
    route.presentExitPush = options.overlay?.exit?.push ?? legacyContentTransition;
    route.presentBackdropBlur = options.overlay?.backdropBlur ?? false;
    route.presentDragDownToDismiss = options.overlay?.dragDownToDismiss ?? false;
    route.resultToken = resultToken;
    this.runOnUI(() => {
      if (route.presentation === ROUTE_PRESENTATION_OVERLAY) {
        // The snapshot must exist before the destination builds, so its very
        // first frame already shows the previous page's pixels.
        this.captureSnapshot(route.presentBackdropBlur)
          .then((pixelMap: image.PixelMap) => {
            route.snapshot = pixelMap;
            this.pushRoute(route, onPushFinished);
          })
          .catch(() => {
            // Without a snapshot the page still opens instantly; the content
            // simply appears without the backdrop choreography.
            this.pushRoute(route, onPushFinished);
          });
        return;
      }
      this.openRoute(route, onPushFinished);
    });
  }

  private performClose(callback: (error: string) => void): void {
    if (this.activeDialogRoute !== undefined) {
      if (this.dialogCloseHandler === undefined) {
        callback('Native router has no dialog host');
        return;
      }
      this.dialogCloseHandler(callback);
      return;
    }
    if (this.pathStack.size() === 0) {
      if (this.abilityContext !== undefined) {
        this.abilityContext.moveAbilityToBackground()
          .then(() => callback(''))
          .catch((error: Error) => callback(`Unable to background the app: ${error.message}`));
        return;
      }
      callback('The root route cannot be closed');
      return;
    }
    const top = this.pathStack.getParamByIndex(this.pathStack.size() - 1) as NativeRoute | undefined;
    const dismiss = top === undefined ? undefined : this.presentDismissers.get(top.nativeBackID);
    if (dismiss !== undefined) {
      // The choreography pops the route itself once the backdrop has
      // restored the previous page's pixels.
      dismiss();
      callback('');
      return;
    }
    this.pathStack.pop();
    callback('');
  }

  private pushRoute(route: NativeRoute, callback: (error: string) => void): void {
    try {
      this.pathStack.pushPath({
        name: NativeRouterController.DESTINATION_NAME,
        param: route,
      });
      callback('');
    } catch (error) {
      callback(`Unable to open native route: ${JSON.stringify(error)}`);
    }
  }

  private openRoute(route: NativeRoute, callback: (error: string) => void): void {
    if (route.presentation !== ROUTE_PRESENTATION_INPUT_DIALOG) {
      this.pushRoute(route, callback);
      return;
    }
    if (this.dialogOpenHandler === undefined) {
      callback('Native router has no dialog host');
      return;
    }
    this.activeDialogRoute = route;
    this.dialogOpenHandler(route, (error: string): void => {
      if (error.length > 0 && this.activeDialogRoute === route) {
        this.activeDialogRoute = undefined;
      }
      callback(error);
    });
  }

  private captureSnapshot(blurred: boolean): Promise<image.PixelMap> {
    const context = this.abilityContext ??
      this.uiContext?.getHostContext() as common.UIAbilityContext | undefined;
    if (context === undefined) {
      return Promise.reject(new Error('Native router has no window context'));
    }
    return window.getLastWindow(context)
      .then((hostWindow) => hostWindow.snapshot())
      .then((pixelMap: image.PixelMap): Promise<image.PixelMap> => {
        if (!blurred) {
          return Promise.resolve(pixelMap);
        }
        return pixelMap.scale(BLURRED_CAPTURE_SCALE, BLURRED_CAPTURE_SCALE)
          .then(() => pixelMap);
      });
  }

  private runOnUI(task: () => void): void {
    if (this.uiContext === undefined) {
      task();
      return;
    }
    this.uiContext.runScopedTask(task);
  }
}
