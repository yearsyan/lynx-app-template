import {
  Behavior,
  LynxContext,
  LynxGenericResourceFetcher,
  LynxTemplateResourceFetcher,
  LynxUpdateMeta,
  LynxView,
  MetaData,
  ModuleClassWrapper,
  TemplateData,
} from '@lynx/lynx';
import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';

import { BundleConfig } from '../config/BundleConfig';
import { DevelopmentSettings } from '../config/DevelopmentSettings';
import { BatteryModule } from '../native/BatteryModule';
import { NativeSensorsController, SensorsModule } from '../native/SensorsModule';
import {
  WebviewModuleBridgeHostAdapter,
  createModuleWebviewBehavior,
} from '../webview/WebviewModuleBridge';
import {
  NativeBackController,
  BackModule,
  NativeBackRegistration,
} from '../native/BackModule';
import { BiometricModule } from '../native/BiometricModule';
import {
  AlbumUtilsModule,
  AlbumUtilsRegistration,
} from '../native/AlbumUtilsModule';
import { ClipboardModule } from '../native/ClipboardModule';
import { DeviceInfoModule } from '../native/DeviceInfoModule';
import {
  DisplayModule,
  DisplayRegistration,
  LynxViewSizeTracker,
} from '../native/DisplayModule';
import {
  FileSystemModule,
  FileSystemRegistration,
} from '../native/FileSystemModule';
import { HapticsModule } from '../native/HapticsModule';
import { KVModule } from '../native/KVModule';
import {
  NativeRoute,
  nativeRouteTransitionType,
  NativeRouterController,
  RouterModule,
} from '../native/RouterModule';
import {
  ScannerModule,
  ScannerRegistration,
} from '../native/ScannerModule';
import {
  NativeStatusBarController,
  StatusBarModule,
  NativeStatusBarRegistration,
} from '../native/StatusBarModule';
import {
  NativeScreenshotRegistration,
  ScreenshotModule,
  screenshotViewContainerId,
  SCREENSHOT_PAGE_ROOT_ID,
} from '../native/ScreenshotModule';
import { SecureStorageModule } from '../native/SecureStorageModule';
import {
  NativeToastRegistration,
  ToastModule,
} from '../native/ToastModule';
import {
  NativeWebSocketController,
  WebSocketModule,
} from '../native/WebSocketModule';
import { LaunchpadGenericResourceFetcher } from '../provider/LaunchpadGenericResourceFetcher';
import { LaunchpadTemplateResourceFetcher } from '../provider/LaunchpadTemplateResourceFetcher';
import { LynxBundleRepository } from '../provider/LynxBundleRepository';
import {
  DevelopmentSettingsEntry,
  DevelopmentSettingsPage,
} from './DevelopmentSettingsUI';

class SafeAreaInsets {
  top: number;
  right: number;
  bottom: number;
  left: number;

  constructor(top: number = 0, right: number = 0, bottom: number = 0, left: number = 0) {
    this.top = top;
    this.right = right;
    this.bottom = bottom;
    this.left = left;
  }

  equals(other: SafeAreaInsets): boolean {
    return this.top === other.top &&
      this.right === other.right &&
      this.bottom === other.bottom &&
      this.left === other.left;
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
  private nativeWebSocketController: NativeWebSocketController = new NativeWebSocketController();
  private nativeSensorsController: NativeSensorsController = new NativeSensorsController();
  private templateResourceFetcher: LynxTemplateResourceFetcher = new LaunchpadTemplateResourceFetcher();
  private genericResourceFetcher: LynxGenericResourceFetcher = new LaunchpadGenericResourceFetcher();
  private bundleRepository: LynxBundleRepository = new LynxBundleRepository();
  private safeAreaInsets: SafeAreaInsets = new SafeAreaInsets();
  private lynxViewSizeTracker: LynxViewSizeTracker = new LynxViewSizeTracker();
  private screenshotTargetId: string = '';
  private metaData: MetaData = new MetaData(nativeEnvironmentData(this.safeAreaInsets, NativeRoute.main()));
  private modules: Map<string, ModuleClassWrapper> = new Map();
  // Explicit Harmony adapter reuses this page's exact module registry.
  private webviewBehaviors: Map<string, Behavior> = new Map();
  private mainWindow: window.Window | undefined = undefined;
  private lynxContext: LynxContext | undefined = undefined;
  private avoidAreaChangeCallback = (_options: window.AvoidAreaOptions): void => {
    this.refreshSafeArea();
  };
  private lynxCreateCallback = (context: LynxContext): void => {
    this.lynxContext = context;
    this.publishNativeEnvironment();
  };
  @State private url: string = '';

  aboutToAppear(): void {
    // ArkUI applies the object passed to a child component after field initializers
    // run. Build route-scoped objects here so they capture the injected route and
    // the Navigation host's shared controller instead of their default values.
    this.screenshotTargetId = screenshotViewContainerId(this.route.nativeBackID);
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
    this.modules = this.createModules(context);
    this.webviewBehaviors = new Map<string, Behavior>([
      [
        'module-webview',
        createModuleWebviewBehavior(
          new WebviewModuleBridgeHostAdapter(this.modules),
        ),
      ],
    ]);
    this.metaData.templateData = nativeEnvironmentData(this.safeAreaInsets, this.route);
    this.url = this.initialURL();
    this.subscribeToSafeArea(context);
    if (this.route.bundle !== BundleConfig.BUNDLE_NAME ||
      this.bundleRepository.developmentURL(this.route.bundle).length > 0) {
      return;
    }
    this.bundleRepository.resolveStartupURL(context).then((url: string) => {
      this.url = url;
      this.bundleRepository.checkForUpdate(context).then((updatedURL: string | null) => {
        if (updatedURL !== null) {
          this.url = updatedURL;
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
    this.nativeWebSocketController.destroy();
    this.nativeSensorsController.destroy();
    this.unsubscribeFromSafeArea();
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

  private createModules(context: common.UIAbilityContext): Map<string, ModuleClassWrapper> {
    const modules = new Map<string, ModuleClassWrapper>();
    modules.set(
      ClipboardModule.NAME,
      new NativeModuleRegistration(ClipboardModule),
    );
    modules.set(
      HapticsModule.NAME,
      new NativeModuleRegistration(HapticsModule),
    );
    modules.set(
      BiometricModule.NAME,
      new NativeModuleRegistration(BiometricModule),
    );
    modules.set(
      AlbumUtilsModule.NAME,
      new NativeModuleRegistration(
        AlbumUtilsModule,
        new AlbumUtilsRegistration(context),
      ),
    );
    modules.set(
      FileSystemModule.NAME,
      new NativeModuleRegistration(
        FileSystemModule,
        new FileSystemRegistration(context),
      ),
    );
    modules.set(
      ScannerModule.NAME,
      new NativeModuleRegistration(
        ScannerModule,
        new ScannerRegistration(context),
      ),
    );
    modules.set(
      KVModule.NAME,
      new NativeModuleRegistration(KVModule),
    );
    modules.set(
      SecureStorageModule.NAME,
      new NativeModuleRegistration(SecureStorageModule),
    );
    modules.set(
      RouterModule.NAME,
      new NativeModuleRegistration(RouterModule, this.routerController),
    );
    modules.set(
      BackModule.NAME,
      new NativeModuleRegistration(
        BackModule,
        new NativeBackRegistration(this.nativeBackController, this.route.nativeBackID),
      ),
    );
    modules.set(
      StatusBarModule.NAME,
      new NativeModuleRegistration(
        StatusBarModule,
        new NativeStatusBarRegistration(
          this.nativeStatusBarController,
          this.route.nativeBackID,
        ),
      ),
    );
    modules.set(
      DeviceInfoModule.NAME,
      new NativeModuleRegistration(DeviceInfoModule),
    );
    modules.set(
      BatteryModule.NAME,
      new NativeModuleRegistration(BatteryModule),
    );
    modules.set(
      SensorsModule.NAME,
      new NativeModuleRegistration(
        SensorsModule,
        this.nativeSensorsController,
      ),
    );
    modules.set(
      DisplayModule.NAME,
      new NativeModuleRegistration(
        DisplayModule,
        new DisplayRegistration(context, this.lynxViewSizeTracker),
      ),
    );
    modules.set(
      ToastModule.NAME,
      new NativeModuleRegistration(
        ToastModule,
        new NativeToastRegistration(this.getUIContext()),
      ),
    );
    modules.set(
      WebSocketModule.NAME,
      new NativeModuleRegistration(
        WebSocketModule,
        this.nativeWebSocketController,
      ),
    );
    modules.set(
      ScreenshotModule.NAME,
      new NativeModuleRegistration(
        ScreenshotModule,
        new NativeScreenshotRegistration(
          this.getUIContext(),
          context,
          this.screenshotTargetId,
          SCREENSHOT_PAGE_ROOT_ID,
        ),
      ),
    );
    return modules;
  }

  private subscribeToSafeArea(context: common.UIAbilityContext): void {
    window.getLastWindow(context).then((mainWindow: window.Window) => {
      this.unsubscribeFromSafeArea();
      this.mainWindow = mainWindow;
      this.refreshSafeArea();
      mainWindow.on('avoidAreaChange', this.avoidAreaChangeCallback);
    }).catch((error: Error) => {
      console.error(`Failed to observe safe area: ${error.message}`);
    });
  }

  private unsubscribeFromSafeArea(): void {
    if (this.mainWindow === undefined) {
      return;
    }
    try {
      this.mainWindow.off('avoidAreaChange', this.avoidAreaChangeCallback);
    } catch (error) {
      console.error(`Failed to stop observing safe area: ${JSON.stringify(error)}`);
    }
    this.mainWindow = undefined;
  }

  private refreshSafeArea(): void {
    if (this.mainWindow === undefined) {
      return;
    }

    let top = 0;
    let right = 0;
    let bottom = 0;
    let left = 0;
    const types: window.AvoidAreaType[] = [
      window.AvoidAreaType.TYPE_SYSTEM,
      window.AvoidAreaType.TYPE_CUTOUT,
      window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR,
    ];
    for (const type of types) {
      try {
        const area = this.mainWindow.getWindowAvoidArea(type);
        if (!area.visible) {
          continue;
        }
        top = Math.max(top, area.topRect.height);
        right = Math.max(right, area.rightRect.width);
        bottom = Math.max(bottom, area.bottomRect.height);
        left = Math.max(left, area.leftRect.width);
      } catch (error) {
        console.error(`Failed to read avoid area ${type}: ${JSON.stringify(error)}`);
      }
    }

    const next = new SafeAreaInsets(
      this.logicalPx(top),
      this.logicalPx(right),
      this.logicalPx(bottom),
      this.logicalPx(left),
    );
    if (this.safeAreaInsets.equals(next)) {
      return;
    }

    this.safeAreaInsets = next;
    this.metaData.templateData = nativeEnvironmentData(next, this.route);
    this.publishNativeEnvironment();
  }

  private logicalPx(value: number): number {
    return Math.round(this.getUIContext().px2vp(value) * 100) / 100;
  }

  private publishNativeEnvironment(): void {
    if (this.lynxContext === undefined) {
      return;
    }
    this.lynxContext.updateMetaData(
      new LynxUpdateMeta(nativeEnvironmentData(this.safeAreaInsets, this.route)),
    );
  }

  build() {
    Column() {
      LynxView({
        templateResourceFetcher: this.templateResourceFetcher,
        genericResourceFetcher: this.genericResourceFetcher,
        modules: this.modules,
        behaviors: this.webviewBehaviors,
        metaData: this.metaData,
        onCreate: this.lynxCreateCallback,
        url: this.url,
      })
        .width('100%')
        .height('100%')
        .onAreaChange((_oldArea: Area, area: Area) => {
          this.lynxViewSizeTracker.widthVp = Number(area.width);
        });
    }
    // Target of the Screenshot module: capturing this container captures the
    // LynxView area of the page.
    .id(this.screenshotTargetId)
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

  aboutToAppear(): void {
    this.routerController.attach(this.getUIContext());
    this.nativeBackController.attach(this.getUIContext());
    this.nativeStatusBarController.attach(this.getUIContext());
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
    // Target of the Screenshot module's page capture: this Stack composes the
    // navigation content plus overlays, i.e. everything the page shows.
    .id(SCREENSHOT_PAGE_ROOT_ID)
    .backgroundColor(Color.Transparent)
    .size({ width: '100%', height: '100%' });
  }
}
