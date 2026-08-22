import { ComponentContent, UIContext } from '@kit.ArkUI';
import { LynxContext, LynxModule } from '@lynx/lynx';

const TYPE_SUCCESS: string = 'success';
const TYPE_ERROR: string = 'error';
const DEFAULT_BACKGROUND: string = '#E62E2A33';
const DEFAULT_TEXT_COLOR: string = '#FFFFFFFF';
const ICON_INFO: string = '#FF8E8A96';
const ICON_SUCCESS: string = '#FF4CAF7D';
const ICON_ERROR: string = '#FFE4556D';
const FADE_MS: number = 200;
const BOTTOM_MARGIN: number = 72;

/** Options mirrored from this package's TypeScript ToastOptions. */
export interface ToastOptions {
  type?: string;
  showIcon?: boolean;
  backgroundColor?: string;
  textColor?: string;
  durationMs?: number;
}

/** Params handed to the toast builder; opacityValue mutates to drive the fades. */
class ToastParams {
  message: string = '';
  type: string = 'info';
  showIcon: boolean = true;
  backgroundColor: string = DEFAULT_BACKGROUND;
  textColor: string = DEFAULT_TEXT_COLOR;
  opacityValue: number = 0;
}

function iconColor(type: string): string {
  if (type === TYPE_SUCCESS) {
    return ICON_SUCCESS;
  }
  if (type === TYPE_ERROR) {
    return ICON_ERROR;
  }
  return ICON_INFO;
}

function iconGlyph(type: string): string {
  if (type === TYPE_SUCCESS) {
    return '✓';
  }
  if (type === TYPE_ERROR) {
    return '✕';
  }
  return 'i';
}

/**
 * The toast bubble plus a transparent full-window carrier. Transparent hit
 * testing keeps the overlay click-through so a toast never swallows touches,
 * matching the passive Android decor-view bubble.
 */
@Builder
function toastOverlay(params: ToastParams) {
  Column() {
    Blank()
    Row() {
      if (params.showIcon) {
        Text(iconGlyph(params.type))
          .fontSize(11)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .textAlign(TextAlign.Center)
          .width(18)
          .height(18)
          .borderRadius(9)
          .backgroundColor(iconColor(params.type))
          .margin({ right: 8 })
      }
      Text(params.message)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(params.textColor)
        .maxLines(3)
    }
    .padding({ left: 14, right: 14, top: 10, bottom: 10 })
    .backgroundColor(params.backgroundColor)
    .borderRadius(24)
    .constraintSize({ maxWidth: '80%' })
    .shadow({ radius: 12, color: '#26000000', offsetX: 0, offsetY: 4 })
    .margin({ bottom: BOTTOM_MARGIN })
  }
  .width('100%')
  .height('100%')
  .alignItems(HorizontalAlign.Center)
  .opacity(params.opacityValue)
  .hitTestBehavior(HitTestMode.Transparent)
}

class ActiveToast {
  content: ComponentContent<ToastParams>;
  params: ToastParams;
  uiContext: UIContext;

  constructor(content: ComponentContent<ToastParams>, params: ToastParams, uiContext: UIContext) {
    this.content = content;
    this.params = params;
    this.uiContext = uiContext;
  }
}

/**
 * One-shot toast exported to Lynx as Toast. The bubble is drawn in the
 * window's own OverlayManager instead of the system toast
 * (promptAction.showToast tints the bubble with a theme blur material that
 * hides custom background colors, renders no icons, and clamps the
 * duration), so colors, the icon circle and the timing match the
 * Android/iOS bubbles exactly and no notification permission is involved.
 * A new toast replaces the previous one.
 */
export class ToastModule extends LynxModule {
  static readonly NAME: string = 'Toast';
  private activeToast: ActiveToast | undefined = undefined;

  constructor(context: LynxContext, param?: Object) {
    super(context, param);
  }

  show(message: string, options: ToastOptions, callback: (error: string) => void): void {
    const currentWindow = this.context.getCurrentWindow();
    if (currentWindow === undefined) {
      callback('Toast has no Lynx window');
      return;
    }
    const durationMs = Math.max(0, Math.round(options.durationMs ?? 2000));
    currentWindow.then((hostWindow) => {
      const uiContext = hostWindow.getUIContext();
      this.removeActive();
      const params = new ToastParams();
      params.message = message;
      params.type = options.type ?? 'info';
      params.showIcon = options.showIcon ?? true;
      params.backgroundColor = options.backgroundColor ?? DEFAULT_BACKGROUND;
      params.textColor = options.textColor ?? DEFAULT_TEXT_COLOR;
      const content =
        new ComponentContent<ToastParams>(uiContext, wrapBuilder<[ToastParams]>(toastOverlay), params);
      const toast = new ActiveToast(content, params, uiContext);
      this.activeToast = toast;
      uiContext.getOverlayManager().addComponentContent(content);
      uiContext.animateTo({ duration: FADE_MS, curve: Curve.EaseOut }, () => {
        params.opacityValue = 1;
        content.update(params);
      });
      setTimeout(() => {
        this.fadeOutActive(toast);
      }, durationMs);
      callback('');
    }).catch((error: Error) => {
      const messageText = error instanceof Error && error.message.length > 0
        ? error.message
        : 'Unable to show the toast';
      callback(messageText);
    });
  }

  /** Drops the current bubble instantly; used when a new toast replaces it. */
  private removeActive(): void {
    const toast = this.activeToast;
    if (toast === undefined) {
      return;
    }
    this.activeToast = undefined;
    toast.uiContext.getOverlayManager().removeComponentContent(toast.content);
  }

  /** Fades the bubble out, then removes it. Stale timers find nothing to do. */
  private fadeOutActive(expected: ActiveToast): void {
    if (this.activeToast !== expected) {
      return;
    }
    this.activeToast = undefined;
    expected.uiContext.animateTo({
      duration: FADE_MS,
      curve: Curve.EaseIn,
      onFinish: () => {
        expected.uiContext.getOverlayManager().removeComponentContent(expected.content);
      },
    }, () => {
      expected.params.opacityValue = 0;
      expected.content.update(expected.params);
    });
  }
}
