import { UIContext } from '@kit.ArkUI';
import { LynxContext, LynxModule } from '@lynx/lynx';

class NativeBackEventPayload {
  platform: string = 'harmony';
  phase: string;
  progress: number;
  source: string = 'system';
  edge: string = 'none';
  touchX: number = 0;
  touchY: number = 0;

  constructor(phase: string, progress: number) {
    this.phase = phase;
    this.progress = progress;
  }
}

class NativeBackSession {
  private enabled: boolean = false;
  private context: LynxContext | undefined = undefined;

  setEnabled(context: LynxContext, enabled: boolean): void {
    this.context = enabled ? context : undefined;
    this.enabled = enabled;
  }

  handleBack(): boolean {
    if (!this.enabled || this.context === undefined) {
      return false;
    }
    this.context.sendGlobalEvent('nativeBack', [new NativeBackEventPayload('start', 0)]);
    this.context.sendGlobalEvent('nativeBack', [new NativeBackEventPayload('commit', 1)]);
    return true;
  }

  destroy(): void {
    this.enabled = false;
    this.context = undefined;
  }
}

/** Owns the active HarmonyOS page's synchronous system Back decision. */
export class NativeBackController {
  private readonly sessions: Map<string, NativeBackSession> = new Map();
  private readonly activeRouteIDs: string[] = [];
  private uiContext: UIContext | undefined = undefined;

  attach(uiContext: UIContext): void {
    this.uiContext = uiContext;
  }

  activate(routeID: string): void {
    if (!this.sessions.has(routeID)) {
      this.sessions.set(routeID, new NativeBackSession());
    }
    const existingIndex = this.activeRouteIDs.indexOf(routeID);
    if (existingIndex >= 0) {
      this.activeRouteIDs.splice(existingIndex, 1);
    }
    this.activeRouteIDs.push(routeID);
  }

  deactivate(routeID: string): void {
    this.sessions.get(routeID)?.destroy();
    this.sessions.delete(routeID);
    const index = this.activeRouteIDs.indexOf(routeID);
    if (index >= 0) {
      this.activeRouteIDs.splice(index, 1);
    }
  }

  setEnabled(
    routeID: string,
    context: LynxContext,
    enabled: boolean,
    callback: (error: string) => void,
  ): void {
    this.runOnUI(() => {
      const session = this.sessions.get(routeID);
      if (session === undefined) {
        callback('Native back page is not active');
        return;
      }
      session.setEnabled(context, enabled);
      callback('');
    });
  }

  handleBack(): boolean {
    if (this.activeRouteIDs.length === 0) {
      return false;
    }
    const routeID = this.activeRouteIDs[this.activeRouteIDs.length - 1];
    return this.sessions.get(routeID)?.handleBack() ?? false;
  }

  private runOnUI(task: () => void): void {
    if (this.uiContext === undefined) {
      task();
      return;
    }
    this.uiContext.runScopedTask(task);
  }
}

export class NativeBackRegistration {
  readonly controller: NativeBackController;
  readonly routeID: string;

  constructor(controller: NativeBackController, routeID: string) {
    this.controller = controller;
    this.routeID = routeID;
  }
}

/** Lets the current Lynx page opt in or out of HarmonyOS system Back interception. */
export class NativeBackModule extends LynxModule {
  static readonly NAME: string = 'NativeBackModule';
  private readonly registration: NativeBackRegistration | undefined;

  constructor(context: LynxContext, param?: Object) {
    super(context, param);
    this.registration = param as NativeBackRegistration | undefined;
  }

  setEnabled(enabled: boolean, callback: (error: string) => void): void {
    if (this.registration === undefined) {
      callback('Native back has no Navigation host');
      return;
    }
    this.registration.controller.setEnabled(
      this.registration.routeID,
      this.context,
      enabled,
      callback,
    );
  }
}
