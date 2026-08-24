import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
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
import { DeepLinkRouteResolver } from '../host/DeepLinkRouteResolver';
import { StartupRoute } from '../host/StartupRoute';
import { LynxBundleRepository } from '../provider/LynxBundleRepository';
import {
  NATIVE_COLOR_SCHEME_KEY,
  NATIVE_LOCALE_KEY,
  resolvedColorScheme,
  resolvedLocale,
} from '../config/NativeEnvironmentConfig';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  private mainWindow: window.Window | undefined = undefined;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    this.publishNativePreferences(this.context.config);
    MMKV.initialize(this.context.getApplicationContext());
    // A cold-start deep link parks its resolution for Index to consume when
    // the page first appears (StartupRoute.deliver falls back to pending).
    this.acceptDeepLinkWant(want);
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
    // Prefetch the OTA version list so page entries can consult it from
    // memory; never blocks ability creation.
    LynxBundleRepository.refreshManifest();
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // A warm deep link reaches the Index handler, which pushes the resolved
    // page onto the Navigation stack.
    this.acceptDeepLinkWant(want);
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    this.publishNativePreferences(newConfig);
    if (this.mainWindow !== undefined) {
      this.applySystemBars(this.mainWindow, newConfig);
    }
  }

  private publishNativePreferences(configuration: Configuration): void {
    AppStorage.setOrCreate<string>(
      NATIVE_COLOR_SCHEME_KEY,
      resolvedColorScheme(configuration),
    );
    AppStorage.setOrCreate<string>(NATIVE_LOCALE_KEY, resolvedLocale(configuration));
  }

  private acceptDeepLinkWant(want: Want): void {
    const resolution = DeepLinkRouteResolver.resolve(this.context, want.uri);
    if (resolution !== null) {
      StartupRoute.deliver(resolution);
    }
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
      this.mainWindow = mainWindow;
      mainWindow.setWindowLayoutFullScreen(true).catch((error: BusinessError) => {
        hilog.error(
          DOMAIN,
          'testTag',
          'Failed to enable immersive layout. Code: %{public}d, message: %{public}s',
          error.code,
          error.message,
        );
      });
      this.applySystemBars(mainWindow, this.context.config);
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });
  }

  private applySystemBars(mainWindow: window.Window, configuration: Configuration): void {
    const isDark = resolvedColorScheme(configuration) === 'dark';
    mainWindow.setWindowSystemBarProperties({
        statusBarColor: '#00000000',
        navigationBarColor: '#00000000',
        statusBarContentColor: isDark ? '#FFF5F5F7' : '#FF1D1B20',
        navigationBarContentColor: isDark ? '#FFF5F5F7' : '#FF1D1B20',
        isStatusBarLightIcon: isDark,
        isNavigationBarLightIcon: isDark,
      }).catch((error: BusinessError) => {
        hilog.error(
          DOMAIN,
          'testTag',
          'Failed to style system bars. Code: %{public}d, message: %{public}s',
          error.code,
          error.message,
        );
      });
  }

  onWindowStageDestroy(): void {
    this.mainWindow = undefined;
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
