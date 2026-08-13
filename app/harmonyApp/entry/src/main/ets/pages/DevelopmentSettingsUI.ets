import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import BuildProfile from 'BuildProfile';

import {
  DevelopmentSettings,
  DevelopmentSettingsSnapshot,
} from '../config/DevelopmentSettings';

/** Floating entry; renders only in Debug builds. */
@Component
export struct DevelopmentSettingsEntry {
  onOpen: () => void = (): void => {};
  @State private safeTop: number = 0;

  aboutToAppear(): void {
    if (!BuildProfile.DEBUG) {
      return;
    }
    const hostContext = this.getUIContext().getHostContext();
    if (hostContext === undefined) {
      return;
    }
    const context: common.UIAbilityContext = hostContext as common.UIAbilityContext;
    window.getLastWindow(context).then((mainWindow: window.Window) => {
      let top: number = 0;
      const types: window.AvoidAreaType[] = [
        window.AvoidAreaType.TYPE_SYSTEM,
        window.AvoidAreaType.TYPE_CUTOUT,
      ];
      for (let index: number = 0; index < types.length; index++) {
        const area = mainWindow.getWindowAvoidArea(types[index]);
        if (area.visible) {
          top = Math.max(top, area.topRect.height);
        }
      }
      this.safeTop = this.getUIContext().px2vp(top);
    }).catch((error: Error) => {
      console.error(`Unable to position Debug settings entry: ${error.message}`);
    });
  }

  build() {
    if (BuildProfile.DEBUG) {
      Button('DEV')
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .width(72)
        .height(34)
        .backgroundColor('#E62B63F1')
        .borderRadius(17)
        .margin({ top: this.safeTop + 10, right: 12 })
        .onClick(() => this.onOpen());
    } else {
      Blank()
        .width(0)
        .height(0);
    }
  }
}

/** Native configuration page; renders only in Debug builds. */
@Component
export struct DevelopmentSettingsPage {
  onClose: (changed: boolean) => void = (_changed: boolean): void => {};
  @State private apiServer: string = '';
  @State private bundleServers: string = '';
  @State private errorMessage: string = '';
  @State private safeTop: number = 0;
  @State private safeBottom: number = 0;

  aboutToAppear(): void {
    if (!BuildProfile.DEBUG) {
      return;
    }
    this.populate(DevelopmentSettings.snapshot());
    this.refreshSafeArea();
  }

  private populate(snapshot: DevelopmentSettingsSnapshot): void {
    this.apiServer = snapshot.apiServer;
    this.bundleServers = snapshot.bundleServers;
    this.errorMessage = '';
  }

  private save(): void {
    try {
      this.populate(DevelopmentSettings.save(this.apiServer, this.bundleServers));
      this.onClose(true);
    } catch (error) {
      this.errorMessage = error instanceof Error
        ? error.message
        : JSON.stringify(error);
    }
  }

  private clear(): void {
    DevelopmentSettings.clear();
    this.populate(DevelopmentSettings.snapshot());
    this.onClose(true);
  }

  private refreshSafeArea(): void {
    const hostContext = this.getUIContext().getHostContext();
    if (hostContext === undefined) {
      return;
    }
    const context: common.UIAbilityContext = hostContext as common.UIAbilityContext;
    window.getLastWindow(context).then((mainWindow: window.Window) => {
      let top: number = 0;
      let bottom: number = 0;
      const types: window.AvoidAreaType[] = [
        window.AvoidAreaType.TYPE_SYSTEM,
        window.AvoidAreaType.TYPE_CUTOUT,
        window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR,
      ];
      for (let index: number = 0; index < types.length; index++) {
        const area = mainWindow.getWindowAvoidArea(types[index]);
        if (!area.visible) {
          continue;
        }
        top = Math.max(top, area.topRect.height);
        bottom = Math.max(bottom, area.bottomRect.height);
      }
      this.safeTop = this.getUIContext().px2vp(top);
      this.safeBottom = this.getUIContext().px2vp(bottom);
    }).catch((error: Error) => {
      console.error(`Unable to read Debug settings safe area: ${error.message}`);
    });
  }

  build() {
    if (BuildProfile.DEBUG) {
      Scroll() {
        Column({ space: 10 }) {
          Row() {
            Text('Lynx development')
              .fontSize(28)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
              .layoutWeight(1);
            Button('Close')
              .fontSize(14)
              .onClick(() => this.onClose(false));
          }
          .width('100%');

          Text('Debug only · saved on this device. Release builds neither expose nor read these values.')
            .fontSize(13)
            .fontColor('#9BB0AA')
            .width('100%');

          Text('API Server')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .margin({ top: 14 })
            .width('100%');
          TextInput({
            placeholder: 'http://192.168.1.10:8080',
            text: this.apiServer,
          })
            .fontColor(Color.White)
            .placeholderColor('#63736E')
            .backgroundColor('#13211E')
            .onChange((value: string) => this.apiServer = value);
          Text('Injected into every bundle as nativeEnvironment.apiServer.')
            .fontSize(13)
            .fontColor('#9BB0AA')
            .width('100%');

          Text('Bundle servers')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .margin({ top: 14 })
            .width('100%');
          TextArea({
            placeholder: 'main=http://192.168.1.10:3000\nnative-capabilities=http://192.168.1.10:3001',
            text: this.bundleServers,
          })
            .height(180)
            .fontColor(Color.White)
            .placeholderColor('#63736E')
            .backgroundColor('#13211E')
            .onChange((value: string) => this.bundleServers = value);
          Text('One bundle-id=URL per line. A server root becomes /<id>.lynx.bundle; a full .lynx.bundle URL is used unchanged.')
            .fontSize(13)
            .fontColor('#9BB0AA')
            .width('100%');

          if (this.errorMessage.length > 0) {
            Text(this.errorMessage)
              .fontSize(14)
              .fontColor('#FF8A80')
              .width('100%');
          }

          Button('Save & reload')
            .width('100%')
            .height(48)
            .fontWeight(FontWeight.Bold)
            .backgroundColor('#2B63F1')
            .onClick(() => this.save());
          Button('Clear overrides & reload')
            .width('100%')
            .height(48)
            .fontWeight(FontWeight.Bold)
            .backgroundColor('#34423E')
            .onClick(() => this.clear());
        }
        .width('100%')
        .padding({
          left: 24,
          right: 24,
          top: this.safeTop + 20,
          bottom: this.safeBottom + 24,
        });
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#07100F');
    } else {
      Blank()
        .width(0)
        .height(0);
    }
  }
}
