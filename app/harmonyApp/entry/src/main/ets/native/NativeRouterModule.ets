import { UIContext } from '@kit.ArkUI';
import { LynxContext, LynxModule } from '@lynx/lynx';

export interface NativeRouteOptions {
  bundle: string;
  presentation?: string;
  transparent?: boolean;
  params?: Record<string, Object>;
}

export class NativeRoute {
  private static nextNativeBackID: number = 0;
  bundle: string;
  presentation: string;
  transparent: boolean;
  params: Record<string, Object>;
  readonly nativeBackID: string;

  constructor(
    bundle: string,
    presentation: string = 'push',
    transparent: boolean = false,
    params: Record<string, Object> = {},
  ) {
    this.bundle = bundle;
    this.presentation = presentation;
    this.transparent = transparent;
    this.params = params;
    this.nativeBackID = `native-back-${NativeRoute.nextNativeBackID}`;
    NativeRoute.nextNativeBackID += 1;
  }

  static main(): NativeRoute {
    return new NativeRoute('main');
  }

  bundleURL(): string {
    return `${this.bundle}.lynx.bundle`;
  }
}

/** Owns ArkUI navigation state while keeping it out of the NativeModule. */
export class NativeRouterController {
  static readonly DESTINATION_NAME: string = 'lynx-bundle';

  private readonly pathStack: NavPathStack;
  private uiContext: UIContext | undefined = undefined;

  constructor(pathStack: NavPathStack) {
    this.pathStack = pathStack;
  }

  attach(uiContext: UIContext): void {
    this.uiContext = uiContext;
  }

  open(route: NativeRoute, callback: (error: string) => void): void {
    this.runOnUI(() => {
      try {
        this.pathStack.pushPath({
          name: NativeRouterController.DESTINATION_NAME,
          param: route,
        });
        callback('');
      } catch (error) {
        callback(`Unable to open native route: ${JSON.stringify(error)}`);
      }
    });
  }

  close(callback: (error: string) => void): void {
    this.runOnUI(() => {
      if (this.pathStack.size() === 0) {
        callback('The root route cannot be closed');
        return;
      }
      this.pathStack.pop();
      callback('');
    });
  }

  private runOnUI(task: () => void): void {
    if (this.uiContext === undefined) {
      task();
      return;
    }
    this.uiContext.runScopedTask(task);
  }
}

/** Opens another Lynx bundle in a NavDestination, including dialog destinations. */
export class NativeRouterModule extends LynxModule {
  static readonly NAME: string = 'NativeRouterModule';
  private readonly router: NativeRouterController | undefined;

  constructor(context: LynxContext, param?: Object) {
    super(context, param);
    this.router = param as NativeRouterController | undefined;
  }

  open(options: NativeRouteOptions, callback: (error: string) => void): void {
    if (!new RegExp('^[a-z0-9][a-z0-9-]*$').test(options.bundle)) {
      callback(`Invalid Lynx bundle name: ${options.bundle}`);
      return;
    }
    if (this.router === undefined) {
      callback('Native router has no Navigation host');
      return;
    }
    const presentation = options.presentation ?? 'push';
    this.router.open(
      new NativeRoute(
        options.bundle,
        presentation,
        options.transparent ?? presentation === 'sheet',
        options.params ?? {},
      ),
      callback,
    );
  }

  close(callback: (error: string) => void): void {
    if (this.router === undefined) {
      callback('Native router has no Navigation host');
      return;
    }
    this.router.close(callback);
  }
}
