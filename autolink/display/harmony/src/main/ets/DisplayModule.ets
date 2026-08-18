import { common } from '@kit.AbilityKit';
import { display, window } from '@kit.ArkUI';
import { settings } from '@kit.BasicServicesKit';
import { LynxContext, LynxModule } from '@lynx/lynx';

class DisplayResult {
  value: number | null;
  error: string;

  constructor(value: number | null = null, error: string = '') {
    this.value = value;
    this.error = error;
  }
}

/** On-demand display metrics exported to Lynx as Display. */
export class DisplayModule extends LynxModule {
  static readonly NAME: string = 'Display';

  constructor(context: LynxContext, param?: Object) {
    super(context, param);
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
      callback(JSON.stringify(new DisplayResult(null, 'Display has no Lynx window')));
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
        callback(JSON.stringify(new DisplayResult(null, 'Display has no Lynx view')));
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
      callback(JSON.stringify(new DisplayResult(null, 'Display has no Lynx window')));
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
        callback(JSON.stringify(new DisplayResult(null, 'Display has no UIAbilityContext')));
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
      callback('Display has no Lynx window');
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
      callback('Display has no Lynx window');
      return;
    }
    try {
      await (await currentWindow).setKeepScreenOn(enabled);
      callback('');
    } catch (error) {
      callback(this.failureMessage(error as Error, 'Unable to change keep-screen-on'));
    }
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
