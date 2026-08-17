import { common } from '@kit.AbilityKit';
import { display, window } from '@kit.ArkUI';
import { LynxContext, LynxModule } from '@lynx/lynx';

class DisplayWidthResult {
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
        new DisplayWidthResult(defaultDisplay.width / defaultDisplay.densityPixels),
      ));
    } catch (error) {
      callback(this.failure(error as Error, 'Unable to read the screen size'));
    }
  }

  async windowWidth(callback: (resultJSON: string) => void): Promise<void> {
    const registration = this.registration;
    if (registration === undefined) {
      callback(JSON.stringify(new DisplayWidthResult(null, 'Display has no UIAbilityContext')));
      return;
    }
    try {
      const mainWindow = await window.getLastWindow(registration.context);
      const widthPx = mainWindow.getWindowProperties().windowRect.width;
      const density = display.getDefaultDisplaySync().densityPixels;
      callback(JSON.stringify(new DisplayWidthResult(widthPx / density)));
    } catch (error) {
      callback(this.failure(error as Error, 'Unable to read the window size'));
    }
  }

  lynxViewWidth(callback: (resultJSON: string) => void): void {
    const registration = this.registration;
    if (registration === undefined) {
      callback(JSON.stringify(new DisplayWidthResult(null, 'Display has no LynxView size tracker')));
      return;
    }
    callback(JSON.stringify(new DisplayWidthResult(registration.viewSize.widthVp)));
  }

  private failure(error: Error, fallback: string): string {
    const message = error.message.length > 0 ? error.message : fallback;
    return JSON.stringify(new DisplayWidthResult(null, message));
  }
}
