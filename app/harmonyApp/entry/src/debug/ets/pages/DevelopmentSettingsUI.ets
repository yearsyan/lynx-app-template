import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import BuildProfile from 'BuildProfile';

import {
  BundleServer,
  DevelopmentSettings,
  DevelopmentSettingsSnapshot,
} from '../config/DevelopmentSettings';

const ENTRY_WIDTH = 72;
const ENTRY_HEIGHT = 34;
const ENTRY_MARGIN = 12;
const ENTRY_TOP_OFFSET = 10;
const POSITION_KEY_X = 'developmentEntryX';
const POSITION_KEY_Y = 'developmentEntryY';

// PersistentStorage must bind each key at most once per process; the entry
// component remounts whenever the settings page opens and closes.
let entryPositionPersistenceBound = false;

/** Floating entry; renders only in Debug builds. */
@Component
export struct DevelopmentSettingsEntry {
  onOpen: () => void = (): void => {};
  @State private safeTop: number = 0;
  @State private safeBottom: number = 0;
  // -1 means window metrics have not loaded yet.
  @State private posX: number = -1;
  @State private posY: number = -1;
  private windowWidth: number = 0;
  private windowHeight: number = 0;
  private panStartX: number = 0;
  private panStartY: number = 0;

  aboutToAppear(): void {
    if (!BuildProfile.DEBUG) {
      return;
    }
    if (!entryPositionPersistenceBound) {
      PersistentStorage.persistProp<number>(POSITION_KEY_X, -1);
      PersistentStorage.persistProp<number>(POSITION_KEY_Y, -1);
      entryPositionPersistenceBound = true;
    }
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
        if (area.visible) {
          top = Math.max(top, area.topRect.height);
          bottom = Math.max(bottom, area.bottomRect.height);
        }
      }
      this.safeTop = this.getUIContext().px2vp(top);
      this.safeBottom = this.getUIContext().px2vp(bottom);
      const windowRect = mainWindow.getWindowProperties().windowRect;
      this.windowWidth = this.getUIContext().px2vp(windowRect.width);
      this.windowHeight = this.getUIContext().px2vp(windowRect.height);
      const storedX: number = AppStorage.get<number>(POSITION_KEY_X) ?? -1;
      const storedY: number = AppStorage.get<number>(POSITION_KEY_Y) ?? -1;
      if (storedX >= 0 && storedY >= 0) {
        this.posX = this.clampX(storedX);
        this.posY = this.clampY(storedY);
      } else {
        this.posX = this.clampX(this.windowWidth - ENTRY_WIDTH - ENTRY_MARGIN);
        this.posY = this.clampY(this.safeTop + ENTRY_TOP_OFFSET);
      }
    }).catch((error: Error) => {
      console.error(`Unable to position Debug settings entry: ${error.message}`);
    });
  }

  private clampX(value: number): number {
    return Math.min(Math.max(value, 0), Math.max(0, this.windowWidth - ENTRY_WIDTH));
  }

  private clampY(value: number): number {
    return Math.min(
      Math.max(value, this.safeTop),
      Math.max(this.safeTop, this.windowHeight - ENTRY_HEIGHT - this.safeBottom),
    );
  }

  build() {
    if (!BuildProfile.DEBUG) {
      Blank()
        .width(0)
        .height(0);
    } else if (this.posX < 0 || this.posY < 0) {
      // Window metrics still loading; keep the pill visible in its old spot.
      Button('DEV')
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .width(ENTRY_WIDTH)
        .height(ENTRY_HEIGHT)
        .backgroundColor('#E62B63F1')
        .borderRadius(17)
        .margin({ top: this.safeTop + ENTRY_TOP_OFFSET, right: ENTRY_MARGIN })
        .onClick(() => this.onOpen());
    } else {
      Button('DEV')
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .width(ENTRY_WIDTH)
        .height(ENTRY_HEIGHT)
        .backgroundColor('#E62B63F1')
        .borderRadius(17)
        .position({ x: this.posX, y: this.posY })
        .gesture(
          PanGesture({ fingers: 1, distance: 5 })
            .onActionStart((event: GestureEvent) => {
              this.panStartX = this.posX;
              this.panStartY = this.posY;
            })
            .onActionUpdate((event: GestureEvent) => {
              this.posX = this.clampX(this.panStartX + event.offsetX);
              this.posY = this.clampY(this.panStartY + event.offsetY);
            })
            .onActionEnd(() => {
              AppStorage.setOrCreate<number>(POSITION_KEY_X, this.posX);
              AppStorage.setOrCreate<number>(POSITION_KEY_Y, this.posY);
            })
        )
        .onClick(() => this.onOpen());
    }
  }
}

/** Native configuration page; renders only in Debug builds. */
@Component
export struct DevelopmentSettingsPage {
  onClose: (changed: boolean) => void = (_changed: boolean): void => {};
  @State private bundleServers: BundleServer[] = [];
  @State private loadedBundleIds: string[] = [];
  @State private editing: boolean = false;
  @State private editingIndex: number = -1;
  @State private selectedLoadedIndex: number = 0;
  @State private draftBundleId: string = '';
  @State private draftServer: string = '';
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
    this.bundleServers = snapshot.bundleServers;
    this.loadedBundleIds = DevelopmentSettings.loadedBundleIds();
    this.cancelEditor();
    this.errorMessage = '';
  }

  private loadedBundleOptions(): SelectOption[] {
    const options: SelectOption[] = [{ value: 'Choose a loaded bundle…' }];
    for (let index: number = 0; index < this.loadedBundleIds.length; index++) {
      options.push({ value: this.loadedBundleIds[index] });
    }
    return options;
  }

  private beginAdd(): void {
    this.editing = true;
    this.editingIndex = -1;
    this.selectedLoadedIndex = 0;
    this.draftBundleId = '';
    this.draftServer = '';
    this.errorMessage = '';
  }

  private beginEdit(index: number): void {
    if (index < 0 || index >= this.bundleServers.length) {
      return;
    }
    const mapping: BundleServer = this.bundleServers[index];
    this.editing = true;
    this.editingIndex = index;
    const loadedIndex: number = this.loadedBundleIds.indexOf(mapping.bundleId);
    this.selectedLoadedIndex = loadedIndex < 0 ? 0 : loadedIndex + 1;
    this.draftBundleId = mapping.bundleId;
    this.draftServer = mapping.server;
    this.errorMessage = '';
  }

  private cancelEditor(): void {
    this.editing = false;
    this.editingIndex = -1;
    this.selectedLoadedIndex = 0;
    this.draftBundleId = '';
    this.draftServer = '';
  }

  private commitEditor(): void {
    try {
      const normalized: BundleServer = DevelopmentSettings.validatedBundleServer(
        this.draftBundleId,
        this.draftServer,
      );
      for (let index: number = 0; index < this.bundleServers.length; index++) {
        if (index !== this.editingIndex &&
          this.bundleServers[index].bundleId === normalized.bundleId) {
          throw new Error(`A server is already configured for ${normalized.bundleId}.`);
        }
      }
      const next: BundleServer[] = this.bundleServers.slice();
      if (this.editingIndex < 0) {
        next.push(normalized);
      } else {
        next[this.editingIndex] = normalized;
      }
      this.bundleServers = next;
      this.cancelEditor();
      this.errorMessage = '';
    } catch (error) {
      this.errorMessage = error instanceof Error
        ? error.message
        : JSON.stringify(error);
    }
  }

  private deleteMapping(index: number): void {
    const next: BundleServer[] = [];
    for (let current: number = 0; current < this.bundleServers.length; current++) {
      if (current !== index) {
        next.push(this.bundleServers[current]);
      }
    }
    this.bundleServers = next;
    if (this.editingIndex === index) {
      this.cancelEditor();
    }
  }

  private save(): void {
    try {
      this.populate(DevelopmentSettings.save(this.bundleServers));
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

          Text('Bundle servers')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .margin({ top: 14 })
            .width('100%');
          Text('Choose a bundle loaded on this device or enter an ID manually. A server root resolves to /<id>.lynx.bundle; a full bundle URL is used unchanged.')
            .fontSize(13)
            .fontColor('#9BB0AA')
            .width('100%');

          if (this.bundleServers.length === 0) {
            Text('No bundle servers configured.')
              .fontSize(14)
              .fontColor('#9BB0AA')
              .width('100%')
              .padding(14)
              .backgroundColor('#13211E')
              .borderRadius(8);
          } else {
            ForEach(this.bundleServers, (mapping: BundleServer, index: number) => {
              Column({ space: 6 }) {
                Text(mapping.bundleId)
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(Color.White)
                  .width('100%');
                Text(mapping.server)
                  .fontSize(13)
                  .fontColor('#B7C8C3')
                  .width('100%');
                Row({ space: 8 }) {
                  Button('Edit')
                    .fontSize(14)
                    .fontColor('#6EA1FF')
                    .layoutWeight(1)
                    .height(38)
                    .backgroundColor('#142C2926')
                    .onClick(() => this.beginEdit(index));
                  Button('Delete')
                    .fontSize(14)
                    .fontColor('#FF8A80')
                    .layoutWeight(1)
                    .height(38)
                    .backgroundColor('#142C2926')
                    .onClick(() => this.deleteMapping(index));
                }
                .width('100%');
              }
              .width('100%')
              .padding(14)
              .backgroundColor('#13211E')
              .borderRadius(8);
            }, (mapping: BundleServer): string =>
              `${mapping.bundleId}:${mapping.server}`);
          }

          if (this.editing) {
            Column({ space: 8 }) {
              Text(this.editingIndex < 0 ? 'Add bundle server' : 'Edit bundle server')
                .fontSize(17)
                .fontWeight(FontWeight.Bold)
                .fontColor(Color.White)
                .width('100%');

              Text('Loaded bundle')
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor('#B7C8C3')
                .width('100%');
              Select(this.loadedBundleOptions())
                .selected(this.selectedLoadedIndex)
                .value(this.selectedLoadedIndex > 0
                  ? this.loadedBundleIds[this.selectedLoadedIndex - 1]
                  : 'Choose a loaded bundle…')
                .fontColor(Color.White)
                .selectedOptionFontColor(Color.White)
                .optionFontColor('#07100F')
                .width('100%')
                .backgroundColor('#1C302C')
                .onSelect((index: number, value: string) => {
                  this.selectedLoadedIndex = index;
                  if (index > 0) {
                    this.draftBundleId = value;
                  }
                });

              Text('Bundle ID (or enter manually)')
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor('#B7C8C3')
                .width('100%');
              TextInput({
                placeholder: 'native-capabilities',
                text: this.draftBundleId,
              })
                .fontColor(Color.White)
                .placeholderColor('#63736E')
                .backgroundColor('#1C302C')
                .onChange((value: string) => this.draftBundleId = value);

              Text('Server URL')
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor('#B7C8C3')
                .width('100%');
              TextInput({
                placeholder: 'http://192.168.1.10:3000',
                text: this.draftServer,
              })
                .fontColor(Color.White)
                .placeholderColor('#63736E')
                .backgroundColor('#1C302C')
                .onChange((value: string) => this.draftServer = value);

              Row({ space: 8 }) {
                Button(this.editingIndex < 0 ? 'Add' : 'Update')
                  .layoutWeight(1)
                  .height(42)
                  .fontWeight(FontWeight.Bold)
                  .backgroundColor('#2B63F1')
                  .onClick(() => this.commitEditor());
                Button('Cancel')
                  .layoutWeight(1)
                  .height(42)
                  .fontWeight(FontWeight.Bold)
                  .backgroundColor('#34423E')
                  .onClick(() => this.cancelEditor());
              }
              .width('100%');
            }
            .width('100%')
            .padding(14)
            .backgroundColor('#0F1D1A')
            .border({ width: 1, color: '#36534B' })
            .borderRadius(8);
          } else {
            Button('Add bundle server')
              .width('100%')
              .height(46)
              .fontWeight(FontWeight.Bold)
              .onClick(() => this.beginAdd());
          }

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
            .margin({ top: 14 })
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
