import { bundleManager, common } from '@kit.AbilityKit';
import { display, UIContext, window } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';
import { i18n } from '@kit.LocalizationKit';
import { LynxContext, LynxModule } from '@lynx/lynx';

export const STATUS_BAR_STYLE_DARK_CONTENT: string = 'dark-content';
export const STATUS_BAR_STYLE_LIGHT_CONTENT: string = 'light-content';

export function isNativeStatusBarStyle(style: string): boolean {
  return style === STATUS_BAR_STYLE_DARK_CONTENT ||
    style === STATUS_BAR_STYLE_LIGHT_CONTENT;
}

export class SafeAreaInsets {
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

function logicalDensity(): number {
  const density = display.getDefaultDisplaySync().densityPixels;
  return density > 0 ? density : 1;
}

function readSafeArea(hostWindow: window.Window): SafeAreaInsets {
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
      const area = hostWindow.getWindowAvoidArea(type);
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
  const density = logicalDensity();
  return new SafeAreaInsets(
    Math.round(top / density * 100) / 100,
    Math.round(right / density * 100) / 100,
    Math.round(bottom / density * 100) / 100,
    Math.round(left / density * 100) / 100,
  );
}

async function applyStatusBarStyle(
  hostWindow: window.Window,
  style: string,
): Promise<void> {
  const darkContent = style === STATUS_BAR_STYLE_DARK_CONTENT;
  await hostWindow.setWindowSystemBarProperties({
    statusBarColor: '#00000000',
    statusBarContentColor: darkContent ? '#FF1D1B20' : '#FFFFFFFF',
    isStatusBarLightIcon: !darkContent,
  });
}

/**
 * Package-owned host adapter that observes the current window's safe area.
 * The host only forwards changes into Lynx template metadata for first-frame
 * and reactive layout; all system API access and unit conversion live here.
 */
export class NativeSafeAreaController {
  private mainWindow: window.Window | undefined = undefined;
  private insets: SafeAreaInsets = new SafeAreaInsets();
  private onChange: ((insets: SafeAreaInsets) => void) | undefined = undefined;
  private attachmentGeneration: number = 0;
  private readonly avoidAreaChangeCallback = (_options: window.AvoidAreaOptions): void => {
    this.refresh();
  };

  attach(uiContext: UIContext, onChange: (insets: SafeAreaInsets) => void): void {
    this.detach();
    this.onChange = onChange;
    const generation = this.attachmentGeneration;
    const hostContext = uiContext.getHostContext();
    if (hostContext === undefined) {
      console.error('Native safe area has no UIAbilityContext');
      this.onChange?.(this.getInsets());
      return;
    }
    window.getLastWindow(hostContext as common.UIAbilityContext)
      .then((mainWindow: window.Window) => {
        if (generation !== this.attachmentGeneration) {
          return;
        }
        this.mainWindow = mainWindow;
        this.refresh(true);
        mainWindow.on('avoidAreaChange', this.avoidAreaChangeCallback);
      })
      .catch((error: Error) => {
        console.error(`Unable to attach native safe area: ${error.message}`);
        if (generation === this.attachmentGeneration) {
          this.onChange?.(this.getInsets());
        }
      });
  }

  detach(): void {
    this.attachmentGeneration += 1;
    const mainWindow = this.mainWindow;
    if (mainWindow !== undefined) {
      try {
        mainWindow.off('avoidAreaChange', this.avoidAreaChangeCallback);
      } catch (error) {
        console.error(`Failed to stop observing safe area: ${JSON.stringify(error)}`);
      }
    }
    this.mainWindow = undefined;
    this.onChange = undefined;
  }

  getInsets(): SafeAreaInsets {
    return new SafeAreaInsets(
      this.insets.top,
      this.insets.right,
      this.insets.bottom,
      this.insets.left,
    );
  }

  private refresh(forceNotify: boolean = false): void {
    const mainWindow = this.mainWindow;
    if (mainWindow === undefined) {
      return;
    }
    const next = readSafeArea(mainWindow);
    if (!forceNotify && this.insets.equals(next)) {
      return;
    }
    this.insets = next;
    this.onChange?.(this.getInsets());
  }
}

/** Owns the window-level status bar while individual Lynx routes come and go. */
export class NativeStatusBarController {
  private mainWindow: window.Window | undefined = undefined;
  private readonly styles: Map<string, string> = new Map();
  private readonly activeRouteIDs: string[] = [];

  attach(uiContext: UIContext): void {
    const hostContext = uiContext.getHostContext();
    if (hostContext === undefined) {
      console.error('Native status bar has no UIAbilityContext');
      return;
    }
    window.getLastWindow(hostContext as common.UIAbilityContext)
      .then((mainWindow: window.Window) => {
        this.mainWindow = mainWindow;
        this.applyCurrentStyle();
      })
      .catch((error: Error) => {
        console.error(`Unable to attach native status bar: ${error.message}`);
      });
  }

  activate(routeID: string, initialStyle: string): void {
    const index = this.activeRouteIDs.indexOf(routeID);
    if (index >= 0) {
      this.activeRouteIDs.splice(index, 1);
    }
    if (!this.styles.has(routeID)) {
      this.styles.set(
        routeID,
        isNativeStatusBarStyle(initialStyle) ? initialStyle : STATUS_BAR_STYLE_DARK_CONTENT,
      );
    }
    this.activeRouteIDs.push(routeID);
    this.applyCurrentStyle();
  }

  deactivate(routeID: string): void {
    const index = this.activeRouteIDs.indexOf(routeID);
    if (index >= 0) {
      this.activeRouteIDs.splice(index, 1);
      this.applyCurrentStyle();
    }
  }

  setStyle(routeID: string, style: string, callback: (error: string) => void): void {
    if (!isNativeStatusBarStyle(style)) {
      callback(`Invalid status bar style: ${style}`);
      return;
    }
    this.styles.set(routeID, style);
    this.applyCurrentStyle(callback);
  }

  private currentStyle(): string {
    const routeID = this.activeRouteIDs[this.activeRouteIDs.length - 1];
    return routeID === undefined
      ? STATUS_BAR_STYLE_DARK_CONTENT
      : this.styles.get(routeID) ?? STATUS_BAR_STYLE_DARK_CONTENT;
  }

  private applyCurrentStyle(callback?: (error: string) => void): void {
    const mainWindow = this.mainWindow;
    if (mainWindow === undefined) {
      callback?.('');
      return;
    }
    applyStatusBarStyle(mainWindow, this.currentStyle())
      .then(() => {
        callback?.('');
      })
      .catch((error: Error) => {
        const message = `Unable to style status bar: ${error.message}`;
        if (callback !== undefined) {
          callback(message);
        } else {
          console.error(message);
        }
      });
  }
}

/** Page-scoped adapters passed to the globally Autolinked DeviceInfo module. */
export class DeviceInfoRegistration {
  readonly safeAreaController: NativeSafeAreaController;
  readonly statusBarController: NativeStatusBarController;
  readonly routeID: string;

  constructor(
    safeAreaController: NativeSafeAreaController,
    statusBarController: NativeStatusBarController,
    routeID: string,
  ) {
    this.safeAreaController = safeAreaController;
    this.statusBarController = statusBarController;
    this.routeID = routeID;
  }

  getSafeAreaInsets(): SafeAreaInsets {
    return this.safeAreaController.getInsets();
  }

  setStatusBarStyle(style: string, callback: (error: string) => void): void {
    this.statusBarController.setStyle(this.routeID, style, callback);
  }
}

class DeviceInfoValue {
  model: string;
  manufacturer: string;
  osVersion: string;
  osApiLevel: number | null;
  appVersion: string;
  appBuild: string;
  density: number;
  locale: string;
  isTablet: boolean;
  isFoldable: boolean;

  constructor() {
    this.model = deviceInfo.productModel;
    this.manufacturer = deviceInfo.brand;
    this.osVersion = deviceInfo.osFullName;
    this.osApiLevel = deviceInfo.sdkApiVersion;
    this.appVersion = '';
    this.appBuild = '';
    try {
      const bundleInfo = bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT,
      );
      this.appVersion = bundleInfo.versionName;
      this.appBuild = String(bundleInfo.versionCode);
    } catch (error) {
      console.error(`Unable to read bundle info: ${JSON.stringify(error)}`);
    }
    this.density = logicalDensity();
    this.locale = i18n.System.getSystemLocale();
    this.isTablet = deviceInfo.deviceType === 'tablet';
    this.isFoldable = this.readFoldable();
  }

  private readFoldable(): boolean {
    try {
      return display.isFoldable();
    } catch (error) {
      console.error(`Unable to read foldable state: ${JSON.stringify(error)}`);
      return false;
    }
  }
}

class DeviceInfoResult {
  value: DeviceInfoValue | null;
  error: string;

  constructor(value: DeviceInfoValue | null, error: string = '') {
    this.value = value;
    this.error = error;
  }
}

class SafeAreaResult {
  value: SafeAreaInsets | null;
  error: string;

  constructor(value: SafeAreaInsets | null, error: string = '') {
    this.value = value;
    this.error = error;
  }
}

/** Device, safe-area and status-bar APIs exported to Lynx as DeviceInfo. */
export class DeviceInfoModule extends LynxModule {
  static readonly NAME: string = 'DeviceInfo';
  private readonly registration: DeviceInfoRegistration | undefined;

  constructor(context: LynxContext, param?: Object) {
    super(context, param);
    this.registration = param as DeviceInfoRegistration | undefined;
  }

  getInfo(callback: (resultJSON: string) => void): void {
    try {
      callback(JSON.stringify(new DeviceInfoResult(new DeviceInfoValue())));
    } catch (error) {
      const message = error instanceof Error ? error.message : JSON.stringify(error);
      callback(JSON.stringify(new DeviceInfoResult(null, message)));
    }
  }

  async getSafeAreaInsets(callback: (resultJSON: string) => void): Promise<void> {
    const registration = this.registration;
    if (registration !== undefined) {
      callback(JSON.stringify(new SafeAreaResult(registration.getSafeAreaInsets())));
      return;
    }
    const currentWindow = this.context.getCurrentWindow();
    if (currentWindow === undefined) {
      callback(JSON.stringify(new SafeAreaResult(null, 'DeviceInfo has no Lynx window')));
      return;
    }
    try {
      callback(JSON.stringify(new SafeAreaResult(readSafeArea(await currentWindow))));
    } catch (error) {
      const message = error instanceof Error ? error.message : JSON.stringify(error);
      callback(JSON.stringify(new SafeAreaResult(null, message)));
    }
  }

  async setStatusBarStyle(style: string, callback: (error: string) => void): Promise<void> {
    if (!isNativeStatusBarStyle(style)) {
      callback(`Invalid status bar style: ${style}`);
      return;
    }
    const registration = this.registration;
    if (registration !== undefined) {
      registration.setStatusBarStyle(style, callback);
      return;
    }
    const currentWindow = this.context.getCurrentWindow();
    if (currentWindow === undefined) {
      callback('DeviceInfo has no Lynx window');
      return;
    }
    try {
      await applyStatusBarStyle(await currentWindow, style);
      callback('');
    } catch (error) {
      const message = error instanceof Error ? error.message : JSON.stringify(error);
      callback(`Unable to style status bar: ${message}`);
    }
  }
}
