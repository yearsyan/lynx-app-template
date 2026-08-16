import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { LLog, LynxEnv, LynxServiceCenter, LynxServiceType } from '@lynx/lynx';
import { LynxBaseServiceCenter, LynxBaseServiceType } from '@lynx/lynx_base';
import { LynxDevToolService } from '@lynx/lynx_devtool_service';
import { LynxLogService } from '@lynx/lynx_log_service';
import { MMKV } from '@tencent/mmkv';
import BuildProfile from 'BuildProfile';

import { LynxTemplateHttpService } from '../service/LynxTemplateHttpService';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    MMKV.initialize(this.context.getApplicationContext());
    // Init LynxService start
    LynxServiceCenter.registerService(LynxServiceType.DevTool, LynxDevToolService.instance);
    LynxServiceCenter.registerService(LynxServiceType.Http, LynxTemplateHttpService.instance);
    LynxBaseServiceCenter.registerService(LynxBaseServiceType.Log, LynxLogService.instance);
    // Init LynxService end
    // Init LynxEnv start
    LLog.useSysLog(true);
    LynxEnv.initialize(this.context);
    let options = new Map<string, string>();
    options.set('App', 'LynxHarmonyEmptyApp');
    options.set('AppVersion', '0.0.1');
    LynxEnv.setAppInfo(options);
    LynxEnv.enableLynxDebug(BuildProfile.DEBUG);
    LynxEnv.enableDevtool(BuildProfile.DEBUG);
    LynxEnv.setLogBoxEnabled(BuildProfile.DEBUG);
    // Init LynxEnv end
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }

      const mainWindow = windowStage.getMainWindowSync();
      mainWindow.setWindowLayoutFullScreen(true).catch((error: BusinessError) => {
        hilog.error(
          DOMAIN,
          'testTag',
          'Failed to enable immersive layout. Code: %{public}d, message: %{public}s',
          error.code,
          error.message,
        );
      });
      mainWindow.setWindowSystemBarProperties({
        statusBarColor: '#00000000',
        navigationBarColor: '#00000000',
        statusBarContentColor: '#FF1D1B20',
        navigationBarContentColor: '#FF1D1B20',
        isStatusBarLightIcon: false,
        isNavigationBarLightIcon: false,
      }).catch((error: BusinessError) => {
        hilog.error(
          DOMAIN,
          'testTag',
          'Failed to style system bars. Code: %{public}d, message: %{public}s',
          error.code,
          error.message,
        );
      });
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}
