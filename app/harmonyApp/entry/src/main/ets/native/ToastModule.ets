import { UIContext } from '@kit.ArkUI';
import { LynxContext, LynxModule } from '@lynx/lynx';

const TYPE_SUCCESS: string = 'success';
const TYPE_ERROR: string = 'error';
const DEFAULT_BACKGROUND: string = '#E62E2A33';
const DEFAULT_TEXT_COLOR: string = '#FFFFFFFF';
// promptAction.showToast only accepts durations inside this window.
const MIN_DURATION_MS: number = 1500;
const MAX_DURATION_MS: number = 10000;

/** Options mirrored from @lynx-app/native-bridge ToastOptions. */
export interface ToastOptions {
  type?: string;
  showIcon?: boolean;
  backgroundColor?: string;
  textColor?: string;
  durationMs?: number;
}

/** Carries the page UIContext so the module can reach PromptAction. */
export class NativeToastRegistration {
  readonly uiContext: UIContext;

  constructor(uiContext: UIContext) {
    this.uiContext = uiContext;
  }
}

/**
 * One-shot toast exported to Lynx as Toast, backed by promptAction.showToast.
 * The ArkUI toast lives inside the app's own window, so it needs no
 * notification permission and honors the requested colors in any theme.
 * Icons are rendered as a text prefix because showToast is text-only.
 */
export class ToastModule extends LynxModule {
  static readonly NAME: string = 'Toast';
  private readonly registration: NativeToastRegistration | undefined;

  constructor(context: LynxContext, param?: Object) {
    super(context, param);
    this.registration = param instanceof NativeToastRegistration ? param : undefined;
  }

  show(message: string, options: ToastOptions, callback: (error: string) => void): void {
    const registration = this.registration;
    if (registration === undefined) {
      callback('Toast has no UIContext');
      return;
    }
    const durationMs = options.durationMs ?? 2000;
    try {
      registration.uiContext.getPromptAction().showToast({
        message: ToastModule.decorate(message, options),
        duration: Math.max(MIN_DURATION_MS, Math.min(MAX_DURATION_MS, Math.round(durationMs))),
        backgroundColor: options.backgroundColor ?? DEFAULT_BACKGROUND,
        textColor: options.textColor ?? DEFAULT_TEXT_COLOR,
      });
      callback('');
    } catch (error) {
      const messageText = error instanceof Error && error.message.length > 0
        ? error.message
        : 'Unable to show the toast';
      callback(messageText);
    }
  }

  private static decorate(message: string, options: ToastOptions): string {
    if (options.showIcon === false) {
      return message;
    }
    if (options.type === TYPE_SUCCESS) {
      return `✓ ${message}`;
    }
    if (options.type === TYPE_ERROR) {
      return `✕ ${message}`;
    }
    return message;
  }
}
