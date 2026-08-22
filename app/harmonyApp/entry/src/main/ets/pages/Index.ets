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
import { DevelopmentSettings } from 'entry/ets/config/DevelopmentSettings';
import {
  WebviewModuleBridgeHostAdapter,
  createModuleWebviewBehavior,
} from '../webview/WebviewModuleBridge';
import {
  NativeRoute,
  nativeRouteTransitionType,
  NativeRouterController,
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

interface SafeAreaInsetsPayload {
  top: number;
  right: number;
  bottom: number;
  left: number;
}

interface NativeEnvironmentPayload {
  schemaVersion: number;
  unit: string;
  safeAreaInsets: SafeAreaInsetsPayload;
}

interface NativeEnvironmentInitData {
  nativeEnvironment: NativeEnvironmentPayload;
  route: NativeRoutePayload;
}

interface NativeRoutePayload {
  bundle: string;
  presentation: string;
  transparent: boolean;
  statusBarStyle: string;
  animation: string;
  params: Record<string, Object>;
}

function nativeEnvironmentData(insets: SafeAreaInsets, route: NativeRoute): TemplateData {
  const data: NativeEnvironmentInitData = {
    nativeEnvironment: {
      schemaVersion: 1,
      unit: 'px',
      safeAreaInsets: {
        top: insets.top,
        right: insets.right,
        bottom: insets.bottom,
        left: insets.left,
      },
    },
    route: {
      bundle: route.bundle,
      presentation: route.presentation,
      transparent: route.transparent,
      statusBarStyle: route.statusBarStyle,
      animation: route.animation,
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
  route: NativeRoute = NativeRoute.main();
  routerController: NativeRouterController = new NativeRouterController(new NavPathStack());
  nativeBackController: NativeBackController = new NativeBackController();
  nativeStatusBarController: NativeStatusBarController = new NativeStatusBarController();
  private templateResourceFetcher: LynxTemplateResourceFetcher = new LaunchpadTemplateResourceFetcher();
  private genericResourceFetcher: LynxGenericResourceFetcher = new LaunchpadGenericResourceFetcher();
  private bundleRepository: LynxBundleRepository = new LynxBundleRepository();
  private safeAreaInsets: SafeAreaInsets = new SafeAreaInsets();
  private safeAreaController: NativeSafeAreaController = new NativeSafeAreaController();
  private metaData: MetaData = new MetaData(nativeEnvironmentData(this.safeAreaInsets, NativeRoute.main()));
  private modules: Map<string, ModuleClassWrapper> = new Map();
  // Explicit Harmony adapter reuses the page-scoped host module registry.
  private webviewBehaviors: Map<string, Behavior> = new Map();
  private lynxContext: LynxContext | undefined = undefined;
  private hasStartedBundle: boolean = false;
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
    // run. Build route-scoped objects here so they capture the injected route and
    // the Navigation host's shared controller instead of their default values.
    this.nativeBackController.activate(this.route.nativeBackID);
    this.nativeStatusBarController.activate(
      this.route.nativeBackID,
      this.route.statusBarStyle,
    );
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
    this.metaData.templateData = nativeEnvironmentData(this.safeAreaInsets, this.route);
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
    this.metaData.templateData = nativeEnvironmentData(insets, this.route);
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
      new LynxUpdateMeta(nativeEnvironmentData(this.safeAreaInsets, this.route)),
    );
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
      clients: [this.bundleLoadFallback],
      url: this.url,
    })
      .width('100%')
      .height('100%');
  }

  build() {
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
    .size({ width: '100%', height: '100%' });
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
  private handleStartupDeepLink = (resolution: DeepLinkResolution): void => {
    this.routerController.open(
      {
        bundle: resolution.bundle,
        presentation: 'push',
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
    this.nativeBackController.attach(this.getUIContext());
    this.nativeStatusBarController.attach(this.getUIContext());
  }

  aboutToDisappear(): void {
    StartupRoute.registerHandler(undefined);
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
      .mode((param as NativeRoute).transparent
        ? NavDestinationMode.DIALOG
        : NavDestinationMode.STANDARD)
      .systemTransition(
        nativeRouteTransitionType((param as NativeRoute).animation))
      .onBackPressed((): boolean => this.nativeBackController.handleBack())
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
