import { bundleManager } from '@kit.AbilityKit';
import { display } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';
import { i18n } from '@kit.LocalizationKit';
import { LynxContext, LynxModule } from '@lynx/lynx';

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
    this.density = display.getDefaultDisplaySync().densityPixels;
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

/** Static device and application facts exported to Lynx as DeviceInfo. */
export class DeviceInfoModule extends LynxModule {
  static readonly NAME: string = 'DeviceInfo';

  constructor(context: LynxContext, param?: Object) {
    super(context, param);
  }

  getInfo(callback: (resultJSON: string) => void): void {
    try {
      callback(JSON.stringify(new DeviceInfoResult(new DeviceInfoValue())));
    } catch (error) {
      const message = error instanceof Error ? error.message : JSON.stringify(error);
      callback(JSON.stringify(new DeviceInfoResult(null, message)));
    }
  }
}
