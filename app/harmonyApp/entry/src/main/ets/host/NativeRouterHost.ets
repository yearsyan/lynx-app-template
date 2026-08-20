import { common } from '@kit.AbilityKit';
import { UIContext } from '@kit.ArkUI';

import { BundleConfig } from '../config/BundleConfig';
import { STATUS_BAR_STYLE_DARK_CONTENT } from '@lynx-template/autolink-device-info';

interface NativeRouteOptions {
  bundle: string;
  presentation?: string;
  transparent?: boolean;
  statusBarStyle?: string;
  animation?: string;
  params?: Record<string, Object>;
}

export const ROUTER_CONTEXT_DATA_KEY: string =
  '@lynx-template/autolink-router/route-handler';

const ROUTE_ANIMATION_DEFAULT: string = 'default';
const ROUTE_ANIMATION_FADE: string = 'fade';
const ROUTE_ANIMATION_NONE: string = 'none';

/** Maps the shared route animation to the ArkUI navigation transition. */
export function nativeRouteTransitionType(animation: string): NavigationSystemTransitionType {
  if (animation === ROUTE_ANIMATION_FADE) {
    return NavigationSystemTransitionType.FADE;
  }
  if (animation === ROUTE_ANIMATION_NONE) {
    return NavigationSystemTransitionType.NONE;
  }
  return NavigationSystemTransitionType.DEFAULT;
}

export class NativeRoute {
  private static nextNativeBackID: number = 0;
  bundle: string;
  presentation: string;
  transparent: boolean;
  statusBarStyle: string;
  animation: string;
  params: Record<string, Object>;
  readonly nativeBackID: string;

  constructor(
    bundle: string,
    presentation: string = 'push',
    transparent: boolean = false,
    statusBarStyle: string = STATUS_BAR_STYLE_DARK_CONTENT,
    animation: string = ROUTE_ANIMATION_DEFAULT,
    params: Record<string, Object> = {},
  ) {
    this.bundle = bundle;
    this.presentation = presentation;
    this.transparent = transparent;
    this.statusBarStyle = statusBarStyle;
    this.animation = animation;
    this.params = params;
    this.nativeBackID = `native-back-${NativeRoute.nextNativeBackID}`;
    NativeRoute.nextNativeBackID += 1;
  }

  static main(): NativeRoute {
    return new NativeRoute('main');
  }

  bundleURL(): string {
    return `${BundleConfig.EMBEDDED_BUNDLE_DIRECTORY}/${this.bundle}.lynx.bundle`;
  }
}

/** Implements the app-specific ArkUI navigation policy used by RouterModule. */
export class NativeRouterController {
  static readonly DESTINATION_NAME: string = 'lynx-bundle';

  private readonly pathStack: NavPathStack;
  private uiContext: UIContext | undefined = undefined;
  private abilityContext: common.UIAbilityContext | undefined = undefined;

  constructor(pathStack: NavPathStack) {
    this.pathStack = pathStack;
  }

  attach(uiContext: UIContext): void {
    this.uiContext = uiContext;
  }

  attachAbility(context: common.UIAbilityContext): void {
    this.abilityContext = context;
  }

  open(options: NativeRouteOptions, callback: (error: string) => void): void {
    const presentation = options.presentation ?? 'push';
    const route = new NativeRoute(
      options.bundle,
      presentation,
      options.transparent ?? presentation === 'sheet',
      options.statusBarStyle ?? STATUS_BAR_STYLE_DARK_CONTENT,
      options.animation ?? ROUTE_ANIMATION_DEFAULT,
      options.params ?? {},
    );
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

  openURL(url: string, callback: (error: string) => void): void {
    if (this.abilityContext === undefined) {
      callback('Native router has no ability context');
      return;
    }
    this.abilityContext.openLink(url)
      .then(() => callback(''))
      .catch((error: Error) => callback(`Unable to open URL: ${error.message}`));
  }

  private runOnUI(task: () => void): void {
    if (this.uiContext === undefined) {
      task();
      return;
    }
    this.uiContext.runScopedTask(task);
  }
}
