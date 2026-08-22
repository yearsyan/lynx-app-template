import { bundleManager, common } from '@kit.AbilityKit';
import { display, UIContext, window } from '@kit.ArkUI';
import { batteryInfo, deviceInfo, settings } from '@kit.BasicServicesKit';
import { i18n } from '@kit.LocalizationKit';
import { sensor } from '@kit.SensorServiceKit';
import { LynxContext, LynxModule, LynxViewClient } from '@lynx/lynx';

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

/** Page-scoped adapters passed to the globally Autolinked Device module. */
export class DeviceRegistration {
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

class DisplayResult {
  value: number | null;
  error: string;

  constructor(value: number | null = null, error: string = '') {
    this.value = value;
    this.error = error;
  }
}

class BatteryValue {
  level: number | null;
  charging: boolean;

  constructor() {
    if (batteryInfo.isBatteryPresent) {
      const soc: number = batteryInfo.batterySOC;
      this.level = soc >= 0 && soc <= 100 ? soc / 100 : null;
    } else {
      this.level = null;
    }
    const status: batteryInfo.BatteryChargeState = batteryInfo.chargingStatus;
    this.charging = status === batteryInfo.BatteryChargeState.ENABLE ||
      status === batteryInfo.BatteryChargeState.FULL;
  }
}

class BatteryResult {
  value: BatteryValue | null;
  error: string;

  constructor(value: BatteryValue | null, error: string = '') {
    this.value = value;
    this.error = error;
  }
}

class SensorEventPayload {
  type: string;
  x: number = 0;
  y: number = 0;
  z: number = 0;
  heading: number = 0;
  accuracy: number = -1;
  timestamp: number = 0;
  error: string = '';

  constructor(type: string) {
    this.type = type;
  }
}

function accuracyDegrees(accuracy: sensor.SensorAccuracy): number {
  if (accuracy === sensor.SensorAccuracy.ACCURACY_HIGH) {
    return 15;
  }
  if (accuracy === sensor.SensorAccuracy.ACCURACY_MEDIUM) {
    return 30;
  }
  if (accuracy === sensor.SensorAccuracy.ACCURACY_LOW) {
    return 45;
  }
  return -1;
}

/** Owns the sensor subscriptions created by one Lynx NativeModule instance. */
class NativeSensorsController {
  private context: LynxContext | undefined = undefined;
  private destroyed: boolean = false;
  private accelerometerCallback: ((data: sensor.AccelerometerResponse) => void) | undefined = undefined;
  private compassCallback: ((data: sensor.OrientationResponse) => void) | undefined = undefined;

  isAvailable(type: string, callback: (resultJSON: string) => void): void {
    try {
      if (type === 'accelerometer') {
        sensor.getSingleSensorSync(sensor.SensorId.ACCELEROMETER);
      } else if (type === 'compass') {
        sensor.getSingleSensorSync(sensor.SensorId.ORIENTATION);
      } else {
        callback('{"error":"Unknown sensor type"}');
        return;
      }
      callback('{"value":true}');
    } catch (error) {
      callback('{"value":false}');
    }
  }

  start(type: string, callback: (error: string) => void, context: LynxContext): void {
    this.destroyed = false;
    this.context = context;
    if (type === 'accelerometer') {
      if (this.accelerometerCallback !== undefined) {
        callback('');
        return;
      }
      try {
        const listener = (data: sensor.AccelerometerResponse): void => {
          const payload = new SensorEventPayload('accelerometer');
          payload.x = data.x;
          payload.y = data.y;
          payload.z = data.z;
          payload.timestamp = Date.now();
          this.emit(payload);
        };
        sensor.on(sensor.SensorId.ACCELEROMETER, listener);
        this.accelerometerCallback = listener;
        callback('');
      } catch (error) {
        callback(this.messageOf(error, 'Unable to start the accelerometer'));
      }
      return;
    }
    if (type === 'compass') {
      if (this.compassCallback !== undefined) {
        callback('');
        return;
      }
      try {
        const listener = (data: sensor.OrientationResponse): void => {
          const payload = new SensorEventPayload('compass');
          payload.heading = data.alpha;
          payload.accuracy = accuracyDegrees(data.accuracy);
          payload.timestamp = Date.now();
          this.emit(payload);
        };
        sensor.on(sensor.SensorId.ORIENTATION, listener);
        this.compassCallback = listener;
        callback('');
      } catch (error) {
        callback(this.messageOf(error, 'Unable to start the compass'));
      }
      return;
    }
    callback('Unknown sensor type');
  }

  stop(type: string, callback: (error: string) => void): void {
    if (type === 'accelerometer') {
      const listener = this.accelerometerCallback;
      if (listener === undefined) {
        callback('');
        return;
      }
      try {
        sensor.off(sensor.SensorId.ACCELEROMETER, listener);
        this.accelerometerCallback = undefined;
        callback('');
      } catch (error) {
        callback(this.messageOf(error, 'Unable to stop the accelerometer'));
      }
      return;
    }
    if (type === 'compass') {
      const listener = this.compassCallback;
      if (listener === undefined) {
        callback('');
        return;
      }
      try {
        sensor.off(sensor.SensorId.ORIENTATION, listener);
        this.compassCallback = undefined;
        callback('');
      } catch (error) {
        callback(this.messageOf(error, 'Unable to stop the compass'));
      }
      return;
    }
    callback('Unknown sensor type');
  }

  destroy(): void {
    this.destroyed = true;
    const accelerometer = this.accelerometerCallback;
    this.accelerometerCallback = undefined;
    if (accelerometer !== undefined) {
      try {
        sensor.off(sensor.SensorId.ACCELEROMETER, accelerometer);
      } catch (_error) {
      }
    }
    const compass = this.compassCallback;
    this.compassCallback = undefined;
    if (compass !== undefined) {
      try {
        sensor.off(sensor.SensorId.ORIENTATION, compass);
      } catch (_error) {
      }
    }
    this.context = undefined;
  }

  private emit(payload: SensorEventPayload): void {
    if (!this.destroyed) {
      this.context?.sendGlobalEvent(DeviceModule.EVENT_NAME, [payload]);
    }
  }

  private messageOf(error: Object, fallback: string): string {
    return error instanceof Error && error.message.length > 0 ? error.message : fallback;
  }
}

class SensorsLifecycleClient extends LynxViewClient {
  private readonly controller: NativeSensorsController;

  constructor(controller: NativeSensorsController) {
    super();
    this.controller = controller;
  }

  override onDestroy(): void {
    this.controller.destroy();
  }
}

/**
 * Device, safe-area, status-bar, display, battery and motion-sensor APIs
 * exported to Lynx as Device. Sensor readings flow back through the
 * module's LynxContext as `sensors` global events.
 */
export class DeviceModule extends LynxModule {
  static readonly NAME: string = 'Device';
  static readonly EVENT_NAME: string = 'sensors';
  private readonly registration: DeviceRegistration | undefined;
  private readonly sensorsController: NativeSensorsController;

  constructor(context: LynxContext, param?: Object) {
    super(context, param);
    this.registration = param as DeviceRegistration | undefined;
    this.sensorsController = new NativeSensorsController();
    context.getLynxViewClient()?.push(new SensorsLifecycleClient(this.sensorsController));
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
      callback(JSON.stringify(new SafeAreaResult(null, 'Device has no Lynx window')));
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
      callback('Device has no Lynx window');
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

  screenWidth(callback: (resultJSON: string) => void): void {
    try {
      const defaultDisplay = display.getDefaultDisplaySync();
      callback(JSON.stringify(
        new DisplayResult(defaultDisplay.width / defaultDisplay.densityPixels),
      ));
    } catch (error) {
      callback(this.failure(error as Error, 'Unable to read the screen size'));
    }
  }

  async windowWidth(callback: (resultJSON: string) => void): Promise<void> {
    const currentWindow = this.context.getCurrentWindow();
    if (currentWindow === undefined) {
      callback(JSON.stringify(new DisplayResult(null, 'Device has no Lynx window')));
      return;
    }
    try {
      const hostWindow = await currentWindow;
      const widthPx = hostWindow.getWindowProperties().windowRect.width;
      const density = display.getDefaultDisplaySync().densityPixels;
      callback(JSON.stringify(new DisplayResult(widthPx / density)));
    } catch (error) {
      callback(this.failure(error as Error, 'Unable to read the window size'));
    }
  }

  lynxViewWidth(callback: (resultJSON: string) => void): void {
    try {
      const owner = this.context.getUIOwner();
      if (owner === undefined) {
        callback(JSON.stringify(new DisplayResult(null, 'Device has no Lynx view')));
        return;
      }
      const rectangle = this.context.getRectangleById('');
      callback(JSON.stringify(new DisplayResult(
        owner.uiContext.px2vp(rectangle.size.width),
      )));
    } catch (error) {
      callback(this.failure(error as Error, 'Unable to read the Lynx view size'));
    }
  }

  /** Returns the active window override or the system brightness, normalized to 0..1. */
  async getBrightness(callback: (resultJSON: string) => void): Promise<void> {
    const currentWindow = this.context.getCurrentWindow();
    if (currentWindow === undefined) {
      callback(JSON.stringify(new DisplayResult(null, 'Device has no Lynx window')));
      return;
    }
    try {
      const hostWindow = await currentWindow;
      const windowBrightness = hostWindow.getWindowProperties().brightness;
      if (windowBrightness >= 0) {
        callback(JSON.stringify(new DisplayResult(windowBrightness)));
        return;
      }
      const abilityContext = this.abilityContext();
      if (abilityContext === undefined) {
        callback(JSON.stringify(new DisplayResult(null, 'Device has no UIAbilityContext')));
        return;
      }
      const systemBrightness = Number(await settings.getValue(
        abilityContext,
        settings.display.SCREEN_BRIGHTNESS_STATUS,
      ));
      if (Number.isNaN(systemBrightness)) {
        callback(JSON.stringify(new DisplayResult(null, 'Invalid system brightness value')));
        return;
      }
      callback(JSON.stringify(new DisplayResult(
        Math.min(255, Math.max(0, systemBrightness)) / 255,
      )));
    } catch (error) {
      callback(this.failure(error as Error, 'Unable to read the screen brightness'));
    }
  }

  async setBrightness(value: number, callback: (error: string) => void): Promise<void> {
    if (typeof value !== 'number' || Number.isNaN(value) || value < 0 || value > 1) {
      callback('Brightness must be between 0 and 1');
      return;
    }
    const currentWindow = this.context.getCurrentWindow();
    if (currentWindow === undefined) {
      callback('Device has no Lynx window');
      return;
    }
    try {
      await (await currentWindow).setWindowBrightness(value);
      callback('');
    } catch (error) {
      callback(this.failureMessage(error as Error, 'Unable to set the screen brightness'));
    }
  }

  async setKeepScreenOn(enabled: boolean, callback: (error: string) => void): Promise<void> {
    const currentWindow = this.context.getCurrentWindow();
    if (currentWindow === undefined) {
      callback('Device has no Lynx window');
      return;
    }
    try {
      await (await currentWindow).setKeepScreenOn(enabled);
      callback('');
    } catch (error) {
      callback(this.failureMessage(error as Error, 'Unable to change keep-screen-on'));
    }
  }

  /** On-demand battery state, delivered as a structured result object. */
  getBatteryInfo(callback: (result: BatteryResult) => void): void {
    try {
      callback(new BatteryResult(new BatteryValue()));
    } catch (error) {
      const message = error instanceof Error ? error.message : JSON.stringify(error);
      callback(new BatteryResult(null, message));
    }
  }

  isAvailable(type: string, callback: (resultJSON: string) => void): void {
    this.sensorsController.isAvailable(type, callback);
  }

  start(type: string, callback: (error: string) => void): void {
    this.sensorsController.start(type, callback, this.context);
  }

  stop(type: string, callback: (error: string) => void): void {
    this.sensorsController.stop(type, callback);
  }

  private abilityContext(): common.UIAbilityContext | undefined {
    const hostContext = this.context.getUIOwner()?.uiContext.getHostContext();
    return hostContext as common.UIAbilityContext | undefined;
  }

  private failure(error: Object, fallback: string): string {
    return JSON.stringify(new DisplayResult(null, this.failureMessage(error, fallback)));
  }

  private failureMessage(error: Object, fallback: string): string {
    return error instanceof Error && error.message.length > 0 ? error.message : fallback;
  }
}
