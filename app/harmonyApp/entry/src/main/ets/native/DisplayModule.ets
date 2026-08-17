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

/**
 * Latest laid-out LynxView width in vp. The HarmonyOS LynxContext does not
 * expose its view, so the host measures it with onAreaChange and keeps this
 * holder current. Zero means the view has not been laid out yet.
 */
export class LynxViewSizeTracker {
  widthVp: number = 0;
}

export class DisplayRegistration {
  readonly context: common.UIAbilityContext;
  readonly viewSize: LynxViewSizeTracker;

  constructor(context: common.UIAbilityContext, viewSize: LynxViewSizeTracker) {
    this.context = context;
    this.viewSize = viewSize;
  }
}

/**
 * On-demand display metrics exported to Lynx as Display. All widths are
 * reported in Lynx logical pixels (vp), the unit Lynx layout consumes.
 */
export class DisplayModule extends LynxModule {
  static readonly NAME: string = 'Display';
  private readonly registration: DisplayRegistration | undefined;

  constructor(context: LynxContext, param?: Object) {
    super(context, param);
    this.registration = param instanceof DisplayRegistration ? param : undefined;
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
    const registration = this.registration;
    if (registration === undefined) {
      callback(JSON.stringify(new DisplayResult(null, 'Display has no UIAbilityContext')));
      return;
    }
    try {
      const mainWindow = await window.getLastWindow(registration.context);
      const widthPx = mainWindow.getWindowProperties().windowRect.width;
      const density = display.getDefaultDisplaySync().densityPixels;
      callback(JSON.stringify(new DisplayResult(widthPx / density)));
    } catch (error) {
      callback(this.failure(error as Error, 'Unable to read the window size'));
    }
  }

  lynxViewWidth(callback: (resultJSON: string) => void): void {
    const registration = this.registration;
    if (registration === undefined) {
      callback(JSON.stringify(new DisplayResult(null, 'Display has no LynxView size tracker')));
      return;
    }
    callback(JSON.stringify(new DisplayResult(registration.viewSize.widthVp)));
  }

  /**
   * Window brightness when the app has overridden it (>= 0), otherwise the
   * system brightness; both are 0..1. Brightness is window-scoped: it applies
   * while the window is visible and needs no permission.
   */
  async getBrightness(callback: (resultJSON: string) => void): Promise<void> {
    const registration = this.registration;
    if (registration === undefined) {
      callback(JSON.stringify(new DisplayResult(null, 'Display has no UIAbilityContext')));
      return;
    }
    try {
      const mainWindow = await window.getLastWindow(registration.context);
      const windowBrightness = mainWindow.getWindowProperties().brightness;
      if (windowBrightness >= 0) {
        callback(JSON.stringify(new DisplayResult(windowBrightness)));
        return;
      }
      const systemBrightness = Number(await settings.getValue(
        registration.context,
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

  async setBrightness(
    value: number,
    callback: (error: string) => void,
  ): Promise<void> {
    const registration = this.registration;
    if (registration === undefined) {
      callback('Display has no UIAbilityContext');
      return;
    }
    if (typeof value !== 'number' || Number.isNaN(value) || value < 0 || value > 1) {
      callback('Brightness must be between 0 and 1');
      return;
    }
    try {
      const mainWindow = await window.getLastWindow(registration.context);
      await mainWindow.setWindowBrightness(value);
      callback('');
    } catch (error) {
      callback(this.failureMessage(error as Error, 'Unable to set the screen brightness'));
    }
  }

  async setKeepScreenOn(
    enabled: boolean,
    callback: (error: string) => void,
  ): Promise<void> {
    const registration = this.registration;
    if (registration === undefined) {
      callback('Display has no UIAbilityContext');
      return;
    }
    try {
      const mainWindow = await window.getLastWindow(registration.context);
      await mainWindow.setKeepScreenOn(enabled);
      callback('');
    } catch (error) {
      callback(this.failureMessage(error as Error, 'Unable to change keep-screen-on'));
    }
  }

  private failure(error: Error, fallback: string): string {
    const message = error.message.length > 0 ? error.message : fallback;
    return JSON.stringify(new DisplayResult(null, message));
  }

  private failureMessage(error: Error, fallback: string): string {
    return error.message.length > 0 ? error.message : fallback;
  }
}
