import { abilityAccessCtrl, bundleManager, common, Permissions } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { notificationManager } from '@kit.NotificationKit';
import { LynxContext, LynxModule } from '@lynx/lynx';

interface NativePermissionQuery {
  type: string;
}

class NativePermissionState {
  status: string;

  constructor(status: string) {
    this.status = status;
  }
}

class NativePermissionResult {
  value: NativePermissionState | null;
  error: string;

  constructor(value: NativePermissionState | null, error: string = '') {
    this.value = value;
    this.error = error;
  }
}

/**
 * Unified runtime permissions exported to Lynx as Permissions.
 *
 * HarmonyOS reports no "never asked" state (checkAccessToken returns the
 * same value before the first prompt and after a refusal), so check maps
 * every not-granted answer to 'denied'; request still shows the system
 * dialog whenever the permission is not granted. 'notifications' uses the
 * notification switch instead of abilityAccessCtrl.
 */
export class PermissionsModule extends LynxModule {
  static readonly NAME: string = 'Permissions';

  private static readonly PERMISSION_BY_TYPE: Map<string, string> = new Map([
    ['camera', 'ohos.permission.CAMERA'],
    ['photoLibrary', 'ohos.permission.READ_IMAGEVIDEO'],
    ['microphone', 'ohos.permission.MICROPHONE'],
  ]);

  private readonly abilityContext: common.UIAbilityContext;
  private readonly atManager: abilityAccessCtrl.AtManager;

  constructor(context: LynxContext, param?: Object) {
    super(context, param);
    this.abilityContext = getContext(this) as common.UIAbilityContext;
    this.atManager = abilityAccessCtrl.createAtManager();
  }

  check(permission: NativePermissionQuery,
    callback: (result: NativePermissionResult) => void): void {
    let type: string;
    try {
      type = this.permissionType(permission);
    } catch (error) {
      callback(new NativePermissionResult(null, this.messageOf(error)));
      return;
    }
    if (type === 'notifications') {
      this.checkNotifications()
        .then((status: string) => {
          callback(new NativePermissionResult(new NativePermissionState(status)));
        })
        .catch((error: BusinessError) => {
          callback(new NativePermissionResult(null, this.messageOf(error)));
        });
      return;
    }
    this.checkAccessToken(type)
      .then((status: string) => {
        callback(new NativePermissionResult(new NativePermissionState(status)));
      })
      .catch((error: BusinessError) => {
        callback(new NativePermissionResult(null, this.messageOf(error)));
      });
  }

  request(permission: NativePermissionQuery,
    callback: (result: NativePermissionResult) => void): void {
    let type: string;
    try {
      type = this.permissionType(permission);
    } catch (error) {
      callback(new NativePermissionResult(null, this.messageOf(error)));
      return;
    }
    if (type === 'notifications') {
      this.requestNotifications()
        .then((status: string) => {
          callback(new NativePermissionResult(new NativePermissionState(status)));
        })
        .catch((error: BusinessError) => {
          callback(new NativePermissionResult(null, this.messageOf(error)));
        });
      return;
    }
    this.requestAccessToken(type)
      .then((status: string) => {
        callback(new NativePermissionResult(new NativePermissionState(status)));
      })
      .catch((error: BusinessError) => {
        callback(new NativePermissionResult(null, this.messageOf(error)));
      });
  }

  private async checkAccessToken(type: string): Promise<string> {
    const permission = PermissionsModule.PERMISSION_BY_TYPE.get(type);
    if (permission === undefined) {
      throw new Error(`Unknown permission type: ${type}`);
    }
    const bundleInfo = await bundleManager.getBundleInfoForSelf(
      bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION,
    );
    const tokenID = bundleInfo.appInfo.accessTokenId;
    const status = await this.atManager.checkAccessToken(
      tokenID,
      permission as Permissions,
    );
    return status === 0 ? 'granted' : 'denied';
  }

  private async requestAccessToken(type: string): Promise<string> {
    const permission = PermissionsModule.PERMISSION_BY_TYPE.get(type);
    if (permission === undefined) {
      throw new Error(`Unknown permission type: ${type}`);
    }
    try {
      // requestPermissionsFromUser resolves without a dialog when the
      // permission is already granted.
      const result = await this.atManager.requestPermissionsFromUser(
        this.abilityContext,
        [permission as Permissions],
      );
      return result.authResults.length > 0 && result.authResults[0] === 0
        ? 'granted'
        : 'denied';
    } catch (error) {
      // The dialog also fails outright when the host module.json5 does not
      // declare the permission; surface that as a denial with context.
      const message = this.messageOf(error as BusinessError);
      throw new Error(`Unable to request ${type}: ${message}`);
    }
  }

  private async checkNotifications(): Promise<string> {
    const enabled = await notificationManager.isNotificationEnabled();
    return enabled ? 'granted' : 'denied';
  }

  private async requestNotifications(): Promise<string> {
    const enabled = await notificationManager.isNotificationEnabled();
    if (enabled) {
      return 'granted';
    }
    try {
      await notificationManager.requestEnableNotification(this.abilityContext);
      return 'granted';
    } catch (error) {
      const business = error as BusinessError;
      // 1600004 means the user refused the enable dialog; anything else is
      // a real system failure worth reporting.
      if (business.code === 1600004) {
        return 'denied';
      }
      throw new Error(`Unable to request notifications: ${business.message}`);
    }
  }

  private permissionType(permission: NativePermissionQuery): string {
    const rawType = permission?.type;
    if (typeof rawType !== 'string') {
      throw new Error('Permissions type must be a string');
    }
    const supported =
      rawType === 'notifications' ||
      PermissionsModule.PERMISSION_BY_TYPE.has(rawType);
    if (!supported) {
      throw new Error(`Unknown permission type: ${rawType}`);
    }
    return rawType;
  }

  private messageOf(error: Error | BusinessError): string {
    const message = error.message;
    return message.length > 0 ? message : 'Unknown permission error';
  }
}
