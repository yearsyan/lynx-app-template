import { common } from '@kit.AbilityKit';
import { UIContext, window } from '@kit.ArkUI';
import { LynxContext, LynxModule } from '@lynx/lynx';

export const STATUS_BAR_STYLE_DARK_CONTENT: string = 'dark-content';
export const STATUS_BAR_STYLE_LIGHT_CONTENT: string = 'light-content';

export function isNativeStatusBarStyle(style: string): boolean {
  return style === STATUS_BAR_STYLE_DARK_CONTENT ||
    style === STATUS_BAR_STYLE_LIGHT_CONTENT;
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
      if (callback !== undefined) {
        // The desired style is already stored and will be applied when the
        // asynchronous Window lookup completes.
        callback('');
      }
      return;
    }
    const darkContent = this.currentStyle() === STATUS_BAR_STYLE_DARK_CONTENT;
    mainWindow.setWindowSystemBarProperties({
      statusBarColor: '#00000000',
      statusBarContentColor: darkContent ? '#FF1D1B20' : '#FFFFFFFF',
      isStatusBarLightIcon: !darkContent,
    }).then(() => {
      if (callback !== undefined) {
        callback('');
      }
    }).catch((error: Error) => {
      const message = `Unable to style status bar: ${error.message}`;
      if (callback !== undefined) {
        callback(message);
      } else {
        console.error(message);
      }
    });
  }
}

export class NativeStatusBarRegistration {
  readonly controller: NativeStatusBarController;
  readonly routeID: string;

  constructor(controller: NativeStatusBarController, routeID: string) {
    this.controller = controller;
    this.routeID = routeID;
  }

  setStyle(style: string, callback: (error: string) => void): void {
    this.controller.setStyle(this.routeID, style, callback);
  }
}

export class NativeStatusBarModule extends LynxModule {
  static readonly NAME: string = 'NativeStatusBarModule';
  private readonly registration: NativeStatusBarRegistration | undefined;

  constructor(context: LynxContext, param?: Object) {
    super(context, param);
    this.registration = param as NativeStatusBarRegistration | undefined;
  }

  setStyle(style: string, callback: (error: string) => void): void {
    if (this.registration === undefined) {
      callback('Native status bar has no Window host');
      return;
    }
    this.registration.setStyle(style, callback);
  }
}
