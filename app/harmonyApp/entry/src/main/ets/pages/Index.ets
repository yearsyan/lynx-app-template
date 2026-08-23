import {
  Behavior,
  LynxContext,
  LynxError,
  LynxGenericResourceFetcher,
  LynxTemplateResourceFetcher,
  LynxUpdateMeta,
  LynxView,
  LynxViewClient,
  MetaData,
  ModuleClassWrapper,
  TemplateData,
} from '@lynx/lynx';
import { common } from '@kit.AbilityKit';
import { inputMethod } from '@kit.IMEKit';
import { LengthMetrics, window } from '@kit.ArkUI';
import {
  BACK_REGISTRATION_CONTEXT_DATA_KEY,
  BackRegistration,
  NativeBackController,
  ROUTE_HANDLER_CONTEXT_DATA_KEY,
} from '@lynx-template/autolink-navigation';
import {
  DeviceModule,
  DeviceRegistration,
  NativeSafeAreaController,
  NativeStatusBarController,
  SafeAreaInsets,
} from '@lynx-template/autolink-device';

import { BundleConfig } from '../config/BundleConfig';
import {
  NATIVE_COLOR_SCHEME_KEY,
  NATIVE_LOCALE_KEY,
} from '../config/NativeEnvironmentConfig';
import { DevelopmentSettings } from 'entry/ets/config/DevelopmentSettings';
import {
  WebviewModuleBridgeHostAdapter,
  createModuleWebviewBehavior,
} from '../webview/WebviewModuleBridge';
import {
  NativeRoute,
  nativeRouteTransitionType,
  NativeRouterController,
  ROUTE_PRESENTATION_INPUT_DIALOG,
  ROUTE_PRESENTATION_OVERLAY,
} from '../host/NativeRouterHost';
import { DeepLinkResolution } from '../host/DeepLinkRouteResolver';
import { StartupRoute } from '../host/StartupRoute';
import { LaunchpadGenericResourceFetcher } from '../provider/LaunchpadGenericResourceFetcher';
import { LaunchpadTemplateResourceFetcher } from '../provider/LaunchpadTemplateResourceFetcher';
import { LynxBundleRepository } from '../provider/LynxBundleRepository';
import {
  DevelopmentSettingsEntry,
  DevelopmentSettingsPage,
} from 'entry/ets/pages/DevelopmentSettingsUI';

// LynxSubErrorCode E_APP_BUNDLE_LOAD_BAD_RESPONSE / _PARSE_FAILED /
// _BAD_BUNDLE: the bundle bytes could not be fetched or parsed (dev server
// offline, broken OTA cache). JS runtime errors are deliberately excluded so
// development mistakes stay visible.
const BUNDLE_LOAD_FAILURE_SUBCODES: number[] = [10203, 10204, 10205];

/**
 * Re-renders from the embedded bundle when the bundle bytes fail to load, so a
 * stopped dev server never leaves a white screen. Runs at most once: if the
 * embedded bundle itself fails, the error keeps surfacing.
 */
class EmbeddedBundleFallbackClient extends LynxViewClient {
  private hasFallenBack: boolean = false;
  private readonly onBundleLoadFailure: () => void;

  constructor(onBundleLoadFailure: () => void) {
    super();
    this.onBundleLoadFailure = onBundleLoadFailure;
  }

  public onReceivedError(error: LynxError): void {
    if (this.hasFallenBack || !error.isFatal()) {
      return;
    }
    if (!BUNDLE_LOAD_FAILURE_SUBCODES.includes(error.getSubCode())) {
      return;
    }
    this.hasFallenBack = true;
    this.onBundleLoadFailure();
  }
}

/**
 * Reveals the content over the present-route snapshot backdrop once its first
 * screen has been painted: until then the page looks identical to the page
 * below it, so opening with no system transition is imperceptible.
 */
class PresentScreenClient extends LynxViewClient {
  private readonly onFirstScreenCallback: () => void;

  constructor(onFirstScreenCallback: () => void) {
    super();
    this.onFirstScreenCallback = onFirstScreenCallback;
  }

  public onFirstScreen(): void {
    this.onFirstScreenCallback();
  }
}

const PRESENT_DURATION_MS: number = 350;
const PRESENT_BACKDROP_SHIFT: number = 0.08;
const PRESENT_CONTENT_SHIFT_PERCENT: number = 100;
const PRESENT_CORNER_RADIUS: number = 12;
const PRESENT_DRAG_COMMIT_PROGRESS: number = 0.25;
const PRESENT_DRAG_COMMIT_VELOCITY: number = 1000;
const PRESENT_DRAG_MIN_DURATION_MS: number = 80;
const DIALOG_KEYBOARD_DEFAULT_HIDE_DURATION_MS: number = 300;
const DIALOG_KEYBOARD_FINAL_FRAME_LEAD_MS: number = 16;
const DIALOG_KEYBOARD_DISMISS_FALLBACK_MS: number =
  DIALOG_KEYBOARD_DEFAULT_HIDE_DURATION_MS - DIALOG_KEYBOARD_FINAL_FRAME_LEAD_MS;
/** Gaussian blur radius (vp) for snapshots captured with a blurred backdrop. */
const PRESENT_BLUR_RADIUS: number = 25;
/** Default present scrim: 35% black. */
const PRESENT_SCRIM_COLOR: string = '#59000000';

interface SafeAreaInsetsPayload {
  top: number;
  right: number;
  bottom: number;
  left: number;
}

interface NativeEnvironmentPayload {
  schemaVersion: number;
  unit: string;
  colorScheme: string;
  locale: string;
  safeAreaInsets: SafeAreaInsetsPayload;
}

interface NativeEnvironmentInitData {
  nativeEnvironment: NativeEnvironmentPayload;
  route: NativeRoutePayload;
}

interface NativeRoutePayload {
  bundle: string;
  statusBarStyle: string;
  animation: string;
  presentation: string;
  params: Record<string, Object>;
}

function nativeEnvironmentData(
  insets: SafeAreaInsets,
  route: NativeRoute,
  colorScheme: string,
  locale: string,
): TemplateData {
  const data: NativeEnvironmentInitData = {
    nativeEnvironment: {
      schemaVersion: 2,
      unit: 'px',
      colorScheme,
      locale,
      safeAreaInsets: {
        top: insets.top,
        right: insets.right,
        bottom: insets.bottom,
        left: insets.left,
      },
    },
    route: {
      bundle: route.bundle,
      statusBarStyle: route.statusBarStyle,
      animation: route.animation,
      presentation: route.presentation,
      params: route.params,
    },
  };
  return new TemplateData(JSON.stringify(data));
}

class NativeModuleRegistration implements ModuleClassWrapper {
  moduleClass: Function;
  param?: Object;

  constructor(moduleClass: Function, param?: Object) {
    this.moduleClass = moduleClass;
    this.param = param;
  }
}

@Component
struct LynxBundlePage {
  @StorageProp(NATIVE_COLOR_SCHEME_KEY) @Watch('onNativePreferencesChanged')
  private colorScheme: string = 'light';
  @StorageProp(NATIVE_LOCALE_KEY) @Watch('onNativePreferencesChanged')
  private locale: string = 'en';
  route: NativeRoute = NativeRoute.main();
  routerController: NativeRouterController = new NativeRouterController(new NavPathStack());
  nativeBackController: NativeBackController = new NativeBackController();
  nativeStatusBarController: NativeStatusBarController = new NativeStatusBarController();
  private templateResourceFetcher: LynxTemplateResourceFetcher = new LaunchpadTemplateResourceFetcher();
  private genericResourceFetcher: LynxGenericResourceFetcher = new LaunchpadGenericResourceFetcher();
  private bundleRepository: LynxBundleRepository = new LynxBundleRepository();
  private safeAreaInsets: SafeAreaInsets = new SafeAreaInsets();
  private safeAreaController: NativeSafeAreaController = new NativeSafeAreaController();
  private metaData: MetaData = new MetaData(nativeEnvironmentData(
    this.safeAreaInsets,
    NativeRoute.main(),
    this.colorScheme,
    this.locale,
  ));
  private modules: Map<string, ModuleClassWrapper> = new Map();
  // Explicit Harmony adapter reuses the page-scoped host module registry.
  private webviewBehaviors: Map<string, Behavior> = new Map();
  private lynxContext: LynxContext | undefined = undefined;
  private hasStartedBundle: boolean = false;
  // Present choreography: 0 keeps the snapshot backdrop fullscreen with the
  // content hidden, 1 shrinks the backdrop behind the revealed content.
  @State private presentFraction: number = 0;
  @State private dismissingPresent: boolean = false;
  @State private presentDragViewportHeight: number = 1;
  private presentDragActive: boolean = false;
  private presentPlayed: boolean = false;
  private presentScreenClient: PresentScreenClient = new PresentScreenClient((): void => {
    this.playPresent();
  });
  // LynxView only reads `url` at creation; bumping this token flips the
  // build branch below so a changed URL recreates the view and reloads.
  @State private lynxReloadToken: number = 0;
  private lynxCreateCallback = (context: LynxContext): void => {
    this.installHostContext(context);
    this.lynxContext = context;
    this.publishNativeEnvironment();
  };
  private lynxBeforeLoadTemplateCallback = (context: LynxContext): void => {
    this.installHostContext(context);
  };
  private bundleLoadFallback: EmbeddedBundleFallbackClient =
    new EmbeddedBundleFallbackClient((): void => {
      this.fallBackToEmbeddedBundle();
    });
  @State private url: string = '';

  aboutToAppear(): void {
    // ArkUI applies the object passed to a child component after field initializers
    // run. Build route-scoped objects here so they capture the injected route
    // and the Navigation host's shared controller instead of their default values.
    this.nativeBackController.activate(this.route.nativeBackID);
    this.nativeStatusBarController.activate(
      this.route.nativeBackID,
      this.route.statusBarStyle,
    );
    if (this.isOverlayRoute()) {
      this.routerController.registerPresentDismiss(
        this.route.nativeBackID,
        (): void => this.playDismissThenPop(),
      );
    }
    DevelopmentSettings.recordLoadedBundle(this.route.bundle);
    const hostContext = this.getUIContext().getHostContext();
    if (hostContext === undefined) {
      console.error('Failed to obtain UIAbilityContext');
      return;
    }
    const context: common.UIAbilityContext = hostContext as common.UIAbilityContext;
    this.routerController.attachAbility(context);
    this.modules = this.createModules();
    this.webviewBehaviors = new Map<string, Behavior>([
      [
        'module-webview',
        createModuleWebviewBehavior(
          new WebviewModuleBridgeHostAdapter(this.modules),
        ),
      ],
    ]);
    this.metaData.templateData = nativeEnvironmentData(
      this.safeAreaInsets,
      this.route,
      this.colorScheme,
      this.locale,
    );
    this.safeAreaController.attach(
      this.getUIContext(),
      (insets: SafeAreaInsets): void => {
        this.acceptSafeAreaInsets(insets);
        this.startBundle(context);
      },
    );
  }

  private setBundleURL(url: string): void {
    if (url === this.url) {
      return;
    }
    this.url = url;
    this.lynxReloadToken += 1;
  }

  private startBundle(context: common.UIAbilityContext): void {
    if (this.hasStartedBundle) {
      return;
    }
    this.hasStartedBundle = true;
    this.setBundleURL(this.initialURL());
    if (this.route.bundle !== BundleConfig.BUNDLE_NAME ||
      this.bundleRepository.developmentURL(this.route.bundle).length > 0) {
      return;
    }
    this.bundleRepository.resolveStartupURL(context).then((url: string) => {
      this.setBundleURL(url);
      this.bundleRepository.checkForUpdate(context).then((updatedURL: string | null) => {
        if (updatedURL !== null) {
          this.setBundleURL(updatedURL);
        }
      }).catch((error: Error) => {
        console.error(`Lynx bundle update failed: ${error.message}`);
      });
    }).catch((error: Error) => {
      console.error(`Lynx bundle resolution failed: ${error.message}`);
    });
  }

  aboutToDisappear(): void {
    this.nativeBackController.deactivate(this.route.nativeBackID);
    this.nativeStatusBarController.deactivate(this.route.nativeBackID);
    this.safeAreaController.detach();
    this.routerController.registerPresentDismiss(this.route.nativeBackID, undefined);
    // Fires only when the route actually leaves the stack (being covered by a
    // nested push keeps the component mounted), so it resolves the opener's
    // pending openForResult on every close path, gestures included.
    this.routerController.completeRouteResult(this.route);
    this.route.snapshot?.release();
  }

  private hasPresentBackdrop(): boolean {
    return this.route.snapshot !== undefined;
  }

  private isOverlayRoute(): boolean {
    return this.route.presentation === ROUTE_PRESENTATION_OVERLAY;
  }

  private isInputDialogRoute(): boolean {
    return this.route.presentation === ROUTE_PRESENTATION_INPUT_DIALOG;
  }

  /** Present routes with the backdrop transition cleared keep a static snapshot. */
  private hasBackdropTransition(): boolean {
    return this.hasPresentBackdrop() && this.route.presentBackdropTransition;
  }

  private hasEnterContentAnimation(): boolean {
    return this.isOverlayRoute() &&
      (this.route.presentEnterOpacity || this.route.presentEnterPush);
  }

  private hasExitContentAnimation(): boolean {
    return this.isOverlayRoute() &&
      (this.route.presentExitOpacity || this.route.presentExitPush);
  }

  /** The scrim follows the entering choreography; static when all parts are off. */
  private playsPresentChoreography(): boolean {
    return this.hasBackdropTransition() || this.hasEnterContentAnimation();
  }

  /** The scrim follows the independently configured exiting choreography. */
  private playsDismissChoreography(): boolean {
    return this.hasBackdropTransition() || this.hasExitContentAnimation();
  }

  private playsActiveChoreography(): boolean {
    return this.dismissingPresent
      ? this.playsDismissChoreography()
      : this.playsPresentChoreography();
  }

  private canBeginPresentDragDown(): boolean {
    return this.route.presentDragDownToDismiss &&
      this.presentPlayed &&
      !this.dismissingPresent &&
      this.presentFraction >= 1 &&
      this.playsDismissChoreography();
  }

  private beginPresentDragDown(): void {
    this.presentDragActive = this.canBeginPresentDragDown();
    if (this.presentDragActive) {
      // The parent's normal-priority gesture runs only after page gestures
      // decline the sequence. Once recognized, ArkUI keeps this PanGesture as
      // the winner until end/cancel, which is the desired drag lock.
      this.dismissingPresent = true;
    }
  }

  private updatePresentDragDown(event: GestureEvent): void {
    if (!this.presentDragActive) {
      return;
    }
    const progress: number = Math.min(
      Math.max(event.offsetY / Math.max(this.presentDragViewportHeight, 1), 0),
      1,
    );
    this.presentFraction = 1 - progress;
  }

  private endPresentDragDown(event: GestureEvent): void {
    if (!this.presentDragActive) {
      return;
    }
    this.updatePresentDragDown(event);
    this.presentDragActive = false;
    const progress: number = 1 - this.presentFraction;
    if (progress >= PRESENT_DRAG_COMMIT_PROGRESS ||
      event.velocityY >= PRESENT_DRAG_COMMIT_VELOCITY) {
      const duration: number = this.presentInteractiveDuration(this.presentFraction);
      this.getUIContext().animateTo(
        { duration: duration, curve: Curve.EaseInOut },
        (): void => {
          this.presentFraction = 0;
        },
      );
      setTimeout((): void => {
        this.routerController.popAfterPresentDismiss();
      }, duration);
      return;
    }
    this.cancelPresentDragDown();
  }

  private cancelPresentDragDown(): void {
    if (!this.presentDragActive && !this.dismissingPresent) {
      return;
    }
    this.presentDragActive = false;
    const duration: number = this.presentInteractiveDuration(1 - this.presentFraction);
    this.getUIContext().animateTo(
      { duration: duration, curve: Curve.EaseInOut },
      (): void => {
        this.presentFraction = 1;
      },
    );
    setTimeout((): void => {
      this.dismissingPresent = false;
    }, duration);
  }

  private presentInteractiveDuration(distance: number): number {
    return Math.max(
      PRESENT_DRAG_MIN_DURATION_MS,
      Math.round(PRESENT_DURATION_MS * Math.min(Math.max(distance, 0), 1)),
    );
  }

  private hasActiveContentOpacity(): boolean {
    if (!this.isOverlayRoute()) {
      return false;
    }
    return this.dismissingPresent
      ? this.route.presentExitOpacity
      : this.route.presentEnterOpacity;
  }

  private hasActiveContentPush(): boolean {
    if (!this.isOverlayRoute()) {
      return false;
    }
    return this.dismissingPresent
      ? this.route.presentExitPush
      : this.route.presentEnterPush;
  }

  /** Plays the open choreography once the content painted its first screen. */
  private playPresent(): void {
    if (this.presentPlayed || !this.isOverlayRoute()) {
      return;
    }
    this.presentPlayed = true;
    if (!this.playsPresentChoreography()) {
      this.presentFraction = 1;
      return;
    }
    this.getUIContext().animateTo(
      {
        duration: PRESENT_DURATION_MS,
        curve: Curve.EaseInOut,
      },
      (): void => {
        this.presentFraction = 1;
      },
    );
  }

  /**
   * Reverses the open choreography and pops with no system transition, so
   * the revealed previous page stays pixel-aligned with the restored
   * snapshot. Before the first screen there is nothing to animate.
   */
  private playDismissThenPop(): void {
    if (!this.presentPlayed) {
      this.routerController.popAfterPresentDismiss();
      return;
    }
    // Both phase configurations resolve to identity and full opacity at 1, so
    // changing phase here is visually continuous even when enter != exit.
    this.dismissingPresent = true;
    this.presentDragActive = false;
    if (!this.playsDismissChoreography()) {
      this.routerController.popAfterPresentDismiss();
      return;
    }
    this.getUIContext().animateTo(
      { duration: PRESENT_DURATION_MS, curve: Curve.EaseInOut },
      (): void => {
        this.presentFraction = 0;
      },
    );
    setTimeout((): void => {
      this.routerController.popAfterPresentDismiss();
    }, PRESENT_DURATION_MS);
  }

  private initialURL(): string {
    const developmentURL: string = this.bundleRepository.developmentURL(this.route.bundle);
    if (developmentURL.length > 0) {
      return developmentURL;
    }
    if (this.route.bundle === BundleConfig.BUNDLE_NAME) {
      return BundleConfig.EMBEDDED_BUNDLE_PATH;
    }
    return this.route.bundleURL();
  }

  private createModules(): Map<string, ModuleClassWrapper> {
    const modules = new Map<string, ModuleClassWrapper>();
    // Package-owned libraries, including Navigation, are installed globally
    // by the HarmonyOS Autolink AppStartup task. Device additionally receives
    // page-owned safe-area/status-bar state through its package adapter.
    modules.set(
      DeviceModule.NAME,
      new NativeModuleRegistration(
        DeviceModule,
        new DeviceRegistration(
          this.safeAreaController,
          this.nativeStatusBarController,
          this.route.nativeBackID,
        ),
      ),
    );
    return modules;
  }

  private installHostContext(context: LynxContext): void {
    const contextData: Record<string, Object> = context.getContextData() ?? {};
    contextData[BACK_REGISTRATION_CONTEXT_DATA_KEY] = new BackRegistration(
      this.nativeBackController,
      this.route.nativeBackID,
    );
    contextData[ROUTE_HANDLER_CONTEXT_DATA_KEY] = this.routerController;
    context.setContextData(contextData);
  }

  private acceptSafeAreaInsets(insets: SafeAreaInsets): void {
    if (this.safeAreaInsets.equals(insets)) {
      return;
    }
    this.safeAreaInsets = insets;
    this.metaData.templateData = nativeEnvironmentData(
      insets,
      this.route,
      this.colorScheme,
      this.locale,
    );
    this.publishNativeEnvironment();
  }

  private fallBackToEmbeddedBundle(): void {
    const embedded: string = this.route.bundle === BundleConfig.BUNDLE_NAME
      ? BundleConfig.EMBEDDED_BUNDLE_PATH
      : this.route.bundleURL();
    if (this.url === embedded) {
      return;
    }
    console.warn(`Lynx bundle ${this.url} failed to load; falling back to ${embedded}`);
    this.setBundleURL(embedded);
  }

  private publishNativeEnvironment(): void {
    if (this.lynxContext === undefined) {
      return;
    }
    this.lynxContext.updateMetaData(
      new LynxUpdateMeta(nativeEnvironmentData(
        this.safeAreaInsets,
        this.route,
        this.colorScheme,
        this.locale,
      )),
    );
  }

  private onNativePreferencesChanged(): void {
    this.metaData.templateData = nativeEnvironmentData(
      this.safeAreaInsets,
      this.route,
      this.colorScheme,
      this.locale,
    );
    this.publishNativeEnvironment();
  }

  @Builder
  private bundleView() {
    LynxView({
      templateResourceFetcher: this.templateResourceFetcher,
      genericResourceFetcher: this.genericResourceFetcher,
      modules: this.modules,
      behaviors: this.webviewBehaviors,
      metaData: this.metaData,
      beforeLoadTemplate: this.lynxBeforeLoadTemplateCallback,
      onCreate: this.lynxCreateCallback,
      clients: this.isOverlayRoute()
        ? [this.bundleLoadFallback, this.presentScreenClient]
        : [this.bundleLoadFallback],
      fitContentHeight: this.isInputDialogRoute(),
      url: this.url,
    })
      .width('100%');
  }

  build() {
    Stack() {
      if (this.hasPresentBackdrop()) {
        // Present-choreography attributes must read this.presentFraction
        // directly in their expressions: routing the read through a getter
        // hides it from the compiled attribute-update dependencies, freezing
        // the attribute at its creation-time value (the missing shrink).
        Image(this.route.snapshot)
          // The destination becomes active immediately with a NONE system
          // transition. Load the already-decoded snapshot synchronously so its
          // texture is ready for that first destination frame instead of
          // briefly exposing the container background.
          .syncLoad(true)
          .objectFit(ImageFit.Fill)
          .width('100%')
          .height('100%')
          .blur(this.route.presentBackdropBlur ? PRESENT_BLUR_RADIUS : 0)
          // Drop below the status bar as it shrinks, bottom edge pinned to
          // the screen bottom (translate before scale keeps the percent
          // unscaled). Shift equals half the scale shift: it cancels the
          // scale's bottom inset, so no black gap opens at the bottom.
          .translate({
            y: `${this.hasBackdropTransition()
              ? PRESENT_BACKDROP_SHIFT * this.presentFraction * 50
              : 0}%`,
          })
          .scale({
            x: this.hasBackdropTransition()
              ? 1 - PRESENT_BACKDROP_SHIFT * this.presentFraction
              : 1,
            y: this.hasBackdropTransition()
              ? 1 - PRESENT_BACKDROP_SHIFT * this.presentFraction
              : 1,
          })
          // Constant top-only corners (iOS containerConcentric style): present
          // from the first frame instead of animating in with the shrink, and
          // scale together with the snapshot via the transform above. The
          // bottom corners stay square where the snapshot meets the screen
          // bottom.
          .borderRadius({
            topLeft: PRESENT_CORNER_RADIUS,
            topRight: PRESENT_CORNER_RADIUS,
          })
        // Stationary dim between the snapshot and the content: the color
        // carries the dimming alpha; the choreography only fades the layer
        // itself in place. With both transitions cleared it is static.
        Column()
          .backgroundColor(this.route.presentScrimColor ?? PRESENT_SCRIM_COLOR)
          .opacity(this.playsActiveChoreography() ? this.presentFraction : 1)
          .size({ width: '100%', height: '100%' })
      }
      Column() {
        if (this.url.length > 0) {
          if (this.lynxReloadToken % 2 === 0) {
            this.bundleView();
          } else {
            this.bundleView();
          }
        }
      }
      .backgroundColor(Color.Transparent)
      .width('100%')
      .height(this.isInputDialogRoute() ? 'auto' : '100%')
      .translate({
        y: `${this.hasActiveContentPush()
          ? (1 - this.presentFraction) * PRESENT_CONTENT_SHIFT_PERCENT
          : 0}%`,
      })
      .opacity(this.hasActiveContentOpacity() ? this.presentFraction : 1)
    }
    // Opaque behind the backdrop so the shrunken snapshot shows solid black
    // margins instead of whatever renders below the Navigation destination.
    .backgroundColor(this.hasPresentBackdrop() ? '#000000' : Color.Transparent)
    .width('100%')
    .height(this.isInputDialogRoute() ? 'auto' : '100%')
    .onAreaChange((_oldValue: Area, newValue: Area): void => {
      if (typeof newValue.height === 'number' && newValue.height > 0) {
        this.presentDragViewportHeight = newValue.height;
      }
    })
    // Normal priority leaves the page's own gesture recognizers first. If no
    // child wins, this downward pan becomes exclusive through finger release.
    .gesture(
      PanGesture({
        fingers: 1,
        direction: this.route.presentDragDownToDismiss && this.isOverlayRoute()
          ? PanDirection.Down
          : PanDirection.None,
        distance: 5,
      })
        .onActionStart((_event: GestureEvent): void => {
          this.beginPresentDragDown();
        })
        .onActionUpdate((event: GestureEvent): void => {
          this.updatePresentDragDown(event);
        })
        .onActionEnd((event: GestureEvent): void => {
          this.endPresentDragDown(event);
        })
        .onActionCancel((): void => {
          this.cancelPresentDragDown();
        }),
      GestureMask.Normal,
    );
  }
}

@CustomDialog
struct LynxBundleDialog {
  controller?: CustomDialogController;
  route: NativeRoute = NativeRoute.main();
  routerController: NativeRouterController = new NativeRouterController(new NavPathStack());
  nativeBackController: NativeBackController = new NativeBackController();
  nativeStatusBarController: NativeStatusBarController = new NativeStatusBarController();

  build() {
    LynxBundlePage({
      route: this.route,
      routerController: this.routerController,
      nativeBackController: this.nativeBackController,
      nativeStatusBarController: this.nativeStatusBarController,
    });
  }
}

@Entry
@Component
struct Index {
  private pathStack: NavPathStack = new NavPathStack();
  private routerController: NativeRouterController = new NativeRouterController(this.pathStack);
  private nativeBackController: NativeBackController = new NativeBackController();
  private nativeStatusBarController: NativeStatusBarController = new NativeStatusBarController();
  private rootRoute: NativeRoute = NativeRoute.main();
  @State private showDevelopmentSettings: boolean = false;
  private dialogController: CustomDialogController | null = null;
  private dialogRoute: NativeRoute | undefined = undefined;
  private dialogKeyboardHeight: number = 0;
  private dialogHasPresentedKeyboard: boolean = false;
  private pendingDialogDismiss: (() => void) | undefined = undefined;
  private pendingDialogCloseCallbacks: Array<(error: string) => void> = [];
  private dialogDismissFallback: number = -1;
  private keyboardWindow: window.Window | undefined = undefined;
  private dialogKeyboardWindow: window.Window | undefined = undefined;
  private keyboardHeightChangeCallback = (height: number): void => {
    this.dialogKeyboardHeight = Math.max(height, 0);
    if (height > 0) {
      this.dialogHasPresentedKeyboard = true;
      return;
    }
    if (this.dialogHasPresentedKeyboard && this.dialogController !== null) {
      this.ensureDialogDismiss();
      // On HarmonyOS versions without keyboardWillHide/keyboardDidHide,
      // keyboardHeightChange reports zero when the hide animation starts.
      // Keep the dialog through that animation, then remove it on its final frame.
      this.scheduleDialogDismiss(DIALOG_KEYBOARD_DISMISS_FALLBACK_MS);
    }
  };
  private keyboardWillHideCallback = (keyboardInfo: window.KeyboardInfo): void => {
    if (!this.dialogHasPresentedKeyboard || this.dialogController === null) {
      return;
    }
    this.ensureDialogDismiss();
    const duration: number = keyboardInfo.animated === false
      ? 0
      : keyboardInfo.config?.duration ?? DIALOG_KEYBOARD_DEFAULT_HIDE_DURATION_MS;
    this.scheduleDialogDismiss(
      Math.max(duration - DIALOG_KEYBOARD_FINAL_FRAME_LEAD_MS, 0),
    );
  };
  private keyboardDidHideCallback = (_keyboardInfo: window.KeyboardInfo): void => {
    if (!this.dialogHasPresentedKeyboard || this.dialogController === null) {
      return;
    }
    this.ensureDialogDismiss();
    this.completeDialogDismiss();
  };
  private handleStartupDeepLink = (resolution: DeepLinkResolution): void => {
    this.routerController.open(
      {
        bundle: resolution.bundle,
        params: resolution.params,
      },
      (_error: string): void => {},
    );
  };

  aboutToAppear(): void {
    // A cold-start deep link replaces the root route before the first build;
    // warm links arrive later through handleStartupDeepLink.
    const pending: DeepLinkResolution | null = StartupRoute.consumePending();
    if (pending !== null) {
      this.rootRoute = new NativeRoute(pending.bundle);
      this.rootRoute.params = pending.params;
    }
    StartupRoute.registerHandler(this.handleStartupDeepLink);
    this.routerController.attach(this.getUIContext());
    this.routerController.attachDialogHost(
      (route: NativeRoute, callback: (error: string) => void): void => {
        this.openDialogRoute(route, callback);
      },
      (callback: (error: string) => void): void => {
        this.closeDialogRoute(callback);
      },
    );
    this.nativeBackController.attach(this.getUIContext());
    this.nativeStatusBarController.attach(this.getUIContext());
    const hostContext = this.getUIContext().getHostContext();
    if (hostContext !== undefined) {
      window.getLastWindow(hostContext as common.UIAbilityContext)
        .then((hostWindow: window.Window): void => {
          this.keyboardWindow = hostWindow;
          hostWindow.on('keyboardHeightChange', this.keyboardHeightChangeCallback);
        })
        .catch((error: Error): void => {
          console.error(`Unable to observe keyboard height: ${error.message}`);
        });
    }
  }

  aboutToDisappear(): void {
    StartupRoute.registerHandler(undefined);
    this.keyboardWindow?.off('keyboardHeightChange', this.keyboardHeightChangeCallback);
    this.keyboardWindow = undefined;
    this.detachDialogKeyboardWindow();
  }

  private openDialogRoute(
    route: NativeRoute,
    callback: (error: string) => void,
  ): void {
    if (this.dialogController !== null) {
      callback('An inputDialog route is already open');
      return;
    }
    this.dialogRoute = route;
    this.dialogKeyboardHeight = 0;
    this.dialogHasPresentedKeyboard = false;
    this.pendingDialogDismiss = undefined;
    this.pendingDialogCloseCallbacks = [];
    try {
      this.dialogController = new CustomDialogController({
        builder: LynxBundleDialog({
          route: route,
          routerController: this.routerController,
          nativeBackController: this.nativeBackController,
          nativeStatusBarController: this.nativeStatusBarController,
        }),
        autoCancel: true,
        alignment: DialogAlignment.Bottom,
        customStyle: true,
        showInSubWindow: true,
        isModal: true,
        width: '100%',
        backgroundColor: Color.Transparent,
        maskColor: '#73000000',
        cornerRadius: 0,
        keyboardAvoidMode: KeyboardAvoidMode.DEFAULT,
        keyboardAvoidDistance: LengthMetrics.vp(0),
        openAnimation: { duration: 0 },
        closeAnimation: { duration: 0 },
        onWillDismiss: (action: DismissDialogAction): void => {
          this.requestDialogDismiss(action.dismiss);
        },
        onDidAppear: (): void => {
          this.attachDialogKeyboardWindow(route);
        },
        onDidDisappear: (): void => {
          this.dialogDidDisappear(route);
        },
      });
      this.dialogController.open();
      callback('');
    } catch (error) {
      this.dialogController = null;
      this.dialogRoute = undefined;
      callback(`Unable to open inputDialog route: ${JSON.stringify(error)}`);
    }
  }

  private attachDialogKeyboardWindow(
    route: NativeRoute,
    attemptsRemaining: number = 4,
  ): void {
    const hostContext = this.getUIContext().getHostContext();
    if (hostContext === undefined || this.dialogRoute !== route) {
      return;
    }
    window.getLastWindow(hostContext as common.UIAbilityContext)
      .then((dialogWindow: window.Window): void => {
        if (this.dialogRoute !== route || this.dialogController === null) {
          return;
        }
        if (dialogWindow.getWindowProperties().type !== window.WindowType.TYPE_DIALOG) {
          if (attemptsRemaining > 0) {
            setTimeout((): void => {
              this.attachDialogKeyboardWindow(route, attemptsRemaining - 1);
            }, 32);
          }
          return;
        }
        this.detachDialogKeyboardWindow();
        this.dialogKeyboardWindow = dialogWindow;
        dialogWindow.on('keyboardHeightChange', this.keyboardHeightChangeCallback);
        try {
          dialogWindow.on('keyboardWillHide', this.keyboardWillHideCallback);
        } catch (error) {
          console.warn(`Unable to observe dialog keyboardWillHide: ${JSON.stringify(error)}`);
        }
        try {
          dialogWindow.on('keyboardDidHide', this.keyboardDidHideCallback);
        } catch (error) {
          console.warn(`Unable to observe dialog keyboardDidHide: ${JSON.stringify(error)}`);
        }
      })
      .catch((error: Error): void => {
        console.error(`Unable to observe dialog keyboard height: ${error.message}`);
      });
  }

  private detachDialogKeyboardWindow(): void {
    this.dialogKeyboardWindow?.off(
      'keyboardHeightChange',
      this.keyboardHeightChangeCallback,
    );
    try {
      this.dialogKeyboardWindow?.off('keyboardWillHide', this.keyboardWillHideCallback);
    } catch (error) {
      console.warn(`Unable to stop observing dialog keyboardWillHide: ${JSON.stringify(error)}`);
    }
    try {
      this.dialogKeyboardWindow?.off('keyboardDidHide', this.keyboardDidHideCallback);
    } catch (error) {
      console.warn(`Unable to stop observing dialog keyboardDidHide: ${JSON.stringify(error)}`);
    }
    this.dialogKeyboardWindow = undefined;
  }

  private closeDialogRoute(callback: (error: string) => void): void {
    if (this.dialogController === null) {
      callback('No inputDialog route is open');
      return;
    }
    this.pendingDialogCloseCallbacks.push(callback);
    this.requestDialogDismiss((): void => {
      this.dialogController?.close();
    });
  }

  private requestDialogDismiss(dismiss: () => void): void {
    if (this.pendingDialogDismiss === undefined) {
      this.pendingDialogDismiss = dismiss;
    }
    // The IME belongs to the dialog subwindow. Always ask that window to
    // release focus first: some devices report its height only after the
    // first animation frame, so a zero here does not prove it is hidden yet.
    this.getUIContext().getFocusController().clearFocus();
    inputMethod.getController().stopInputSession().catch((): void => {});
    // keyboardWillHide/keyboardDidHide are API 20 capabilities and are absent on
    // some devices. Their fallback must match the system's ~300 ms IME animation;
    // the old 450 ms timeout left the LynxView visible after the IME was gone.
    this.scheduleDialogDismiss(DIALOG_KEYBOARD_DISMISS_FALLBACK_MS);
  }

  private ensureDialogDismiss(): void {
    if (this.pendingDialogDismiss !== undefined) {
      return;
    }
    this.pendingDialogDismiss = (): void => {
      this.dialogController?.close();
    };
  }

  private scheduleDialogDismiss(delay: number): void {
    if (this.dialogDismissFallback >= 0) {
      clearTimeout(this.dialogDismissFallback);
    }
    this.dialogDismissFallback = setTimeout((): void => {
      this.completeDialogDismiss();
    }, delay);
  }

  private completeDialogDismiss(): void {
    const dismiss = this.pendingDialogDismiss;
    if (dismiss === undefined) {
      return;
    }
    this.pendingDialogDismiss = undefined;
    if (this.dialogDismissFallback >= 0) {
      clearTimeout(this.dialogDismissFallback);
      this.dialogDismissFallback = -1;
    }
    dismiss();
  }

  private dialogDidDisappear(route: NativeRoute): void {
    this.detachDialogKeyboardWindow();
    if (this.dialogDismissFallback >= 0) {
      clearTimeout(this.dialogDismissFallback);
      this.dialogDismissFallback = -1;
    }
    this.routerController.completeRouteResult(route);
    this.dialogController = null;
    this.dialogRoute = undefined;
    this.dialogKeyboardHeight = 0;
    this.dialogHasPresentedKeyboard = false;
    this.pendingDialogDismiss = undefined;
    const callbacks = this.pendingDialogCloseCallbacks;
    this.pendingDialogCloseCallbacks = [];
    callbacks.forEach((callback: (error: string) => void): void => callback(''));
  }

  @Builder
  destinationBuilder(name: string, param: Object) {
    if (name === NativeRouterController.DESTINATION_NAME) {
      NavDestination() {
        LynxBundlePage({
          route: param as NativeRoute,
          routerController: this.routerController,
          nativeBackController: this.nativeBackController,
          nativeStatusBarController: this.nativeStatusBarController,
        });
      }
      .hideTitleBar(true)
      .systemTransition(
        nativeRouteTransitionType((param as NativeRoute).animation))
      .onBackPressed((): boolean => {
        if (this.nativeBackController.handleBack()) {
          return true;
        }
        // Present routes replay the open choreography in reverse before the
        // route really pops, so the revealed page stays pixel-aligned.
        const dismiss = this.routerController.presentDismissFor(
          (param as NativeRoute).nativeBackID,
        );
        if (dismiss !== undefined) {
          dismiss();
          return true;
        }
        return false;
      })
      .backgroundColor(Color.Transparent);
    }
  }

  onBackPress(): boolean {
    if (this.showDevelopmentSettings) {
      this.showDevelopmentSettings = false;
      return true;
    }
    return this.nativeBackController.handleBack();
  }

  build() {
    Stack({ alignContent: Alignment.TopEnd }) {
      if (this.showDevelopmentSettings) {
        DevelopmentSettingsPage({
          onClose: (_changed: boolean): void => {
            this.showDevelopmentSettings = false;
          },
        });
      } else {
        Navigation(this.pathStack) {
          LynxBundlePage({
            route: this.rootRoute,
            routerController: this.routerController,
            nativeBackController: this.nativeBackController,
            nativeStatusBarController: this.nativeStatusBarController,
          });
        }
        .hideTitleBar(true)
        .mode(NavigationMode.Stack)
        .navDestination(this.destinationBuilder)
        .backgroundColor(Color.Transparent)
        .size({ width: '100%', height: '100%' });

        DevelopmentSettingsEntry({
          onOpen: (): void => {
            this.showDevelopmentSettings = true;
          },
        });
      }
    }
    .backgroundColor(Color.Transparent)
    .size({ width: '100%', height: '100%' });
  }
}
