import {
  EventHandlerArray,
  LynxUIMethodConstants,
  UIBase,
} from '@lynx/lynx';
import { webview } from '@kit.ArkWeb';

interface WebViewMessageDetail {
  msg: string;
}

interface WebViewErrorDetail {
  errorCode: number;
  errorMsg: string;
}

interface WebViewEvalResult {
  result?: string;
  errorMsg?: string;
}

/** The only ArkWeb object exposed to page JavaScript. */
class NativeWebViewMessageBridge {
  private ui: NativeWebViewUI;

  constructor(ui: NativeWebViewUI) {
    this.ui = ui;
  }

  postMessage(message: string): void {
    this.ui.emitMessage(message);
  }
}

@ObservedV2
class NativeWebViewParams {
  readonly controller: webview.WebviewController = new webview.WebviewController();
  readonly messageBridge: NativeWebViewMessageBridge;
  readonly ui: NativeWebViewUI;

  constructor(ui: NativeWebViewUI) {
    this.ui = ui;
    this.messageBridge = new NativeWebViewMessageBridge(ui);
  }
}

@ComponentV2
struct NativeWebViewComponent {
  @Param @Require webViewParams: NativeWebViewParams;

  build() {
    Web({
      src: 'about:blank',
      controller: this.webViewParams.controller,
    })
      .id(this.webViewParams.ui.sign.toString())
      .width('100%')
      .height('100%')
      .javaScriptAccess(true)
      .domStorageAccess(true)
      .fileAccess(false)
      .zoomAccess(false)
      .javaScriptProxy({
        object: this.webViewParams.messageBridge,
        name: 'LynxWebViewNativeBridge',
        methodList: ['postMessage'],
        controller: this.webViewParams.controller,
      })
      .onControllerAttached(() => {
        this.webViewParams.ui.handleControllerAttached();
      })
      .onPageEnd((event: OnPageEndEvent) => {
        this.webViewParams.ui.handlePageEnd(event.url);
      })
      .onErrorReceive((event: OnErrorReceiveEvent) => {
        if (event.request.isMainFrame()) {
          this.webViewParams.ui.emitError(
            event.error.getErrorCode(),
            event.error.getErrorInfo(),
          );
        }
      });
  }
}

@Builder
export function buildNativeWebView(ui: UIBase) {
  if (ui as NativeWebViewUI) {
    NativeWebViewComponent({
      webViewParams: (ui as NativeWebViewUI).webViewParams,
    });
  }
}

/** HarmonyOS implementation of Lynx's cross-platform <webview> contract. */
export class NativeWebViewUI extends UIBase {
  readonly webViewParams: NativeWebViewParams = new NativeWebViewParams(this);
  readonly builder: WrappedBuilder<[UIBase]> =
    wrapBuilder<[UIBase]>(buildNativeWebView);

  private source: string = '';
  private html: string = '';
  private controllerAttached: boolean = false;
  private retriedAfterInitialBlank: boolean = false;

  static readonly PropSetter: Map<string, Function> = new Map([
    [
      'src',
      (ui: NativeWebViewUI, value: Object): void => {
        ui.source = typeof value === 'string' ? value : '';
      },
    ],
    [
      'html',
      (ui: NativeWebViewUI, value: Object): void => {
        ui.html = typeof value === 'string' ? value : '';
      },
    ],
    [
      'enable-debug',
      (_ui: NativeWebViewUI, value: Object): void => {
        webview.WebviewController.setWebDebuggingAccess(value === true);
      },
    ],
  ]);

  override update(
    props: Record<string, Object>,
    events?: EventHandlerArray[],
  ): void {
    let sourceChanged = false;
    for (const entry of Object.entries(props)) {
      NativeWebViewUI.PropSetter.get(entry[0])?.(this, entry[1]);
      if (entry[0] === 'src' || entry[0] === 'html') {
        sourceChanged = true;
      }
    }
    super.update(props, events);
    if (sourceChanged) {
      this.retriedAfterInitialBlank = false;
      this.loadCurrentSource();
    }
  }

  handleControllerAttached(): void {
    this.controllerAttached = true;
    this.loadCurrentSource();
  }

  handlePageEnd(url: string): void {
    if (url === 'about:blank' && (this.source.length > 0 || this.html.length > 0)) {
      // The declarative about:blank load can finish after onControllerAttached
      // and replace an imperative loadUrl call. Retry once after that initial
      // navigation has settled.
      if (!this.retriedAfterInitialBlank) {
        this.retriedAfterInitialBlank = true;
        this.loadCurrentSource();
      }
      return;
    }
    this.sendCustomEvent('load', new Object(), 'detail');
  }

  emitMessage(message: string): void {
    this.sendCustomEvent(
      'message',
      { msg: message } as WebViewMessageDetail,
      'detail',
    );
  }

  emitError(errorCode: number, errorMsg: string): void {
    this.sendCustomEvent(
      'error',
      { errorCode: errorCode, errorMsg: errorMsg } as WebViewErrorDetail,
      'detail',
    );
  }

  override invokeMethod(
    method: string,
    params: Object,
    callback: (code: number, response: Object) => void,
  ): boolean {
    switch (method) {
      case 'eval':
        this.evaluateJavaScript(params, callback);
        return true;
      case 'reload':
        this.reload(callback);
        return true;
      default:
        return false;
    }
  }

  private loadCurrentSource(): void {
    if (!this.controllerAttached) {
      return;
    }
    try {
      if (this.source.length > 0) {
        this.webViewParams.controller.loadUrl(this.source);
      } else if (this.html.length > 0) {
        // ArkWeb expects loadData payloads to be URL- or Base64-encoded.
        this.webViewParams.controller.loadData(
          encodeURIComponent(this.html),
          'text/html',
          'UTF-8',
        );
      } else {
        this.webViewParams.controller.loadUrl('about:blank');
      }
    } catch (error) {
      this.emitError(-1, `Unable to load WebView content: ${JSON.stringify(error)}`);
    }
  }

  private evaluateJavaScript(
    params: Object,
    callback: (code: number, response: Object) => void,
  ): void {
    const func = (params as Record<string, Object>)['func'];
    if (typeof func !== 'string') {
      callback(
        LynxUIMethodConstants.PARAM_INVALID,
        { errorMsg: 'eval requires a string func parameter' } as WebViewEvalResult,
      );
      return;
    }

    try {
      this.webViewParams.controller.runJavaScript(func)
        .then((result: string) => {
          callback(
            LynxUIMethodConstants.SUCCESS,
            { result: result } as WebViewEvalResult,
          );
        })
        .catch((error: Error) => {
          callback(
            LynxUIMethodConstants.OPERATION_ERROR,
            { errorMsg: error.message } as WebViewEvalResult,
          );
        });
    } catch (error) {
      callback(
        LynxUIMethodConstants.INVALID_STATE_ERROR,
        { errorMsg: JSON.stringify(error) } as WebViewEvalResult,
      );
    }
  }

  private reload(callback: (code: number, response: Object) => void): void {
    try {
      this.webViewParams.controller.refresh();
      callback(LynxUIMethodConstants.SUCCESS, new Object());
    } catch (error) {
      callback(
        LynxUIMethodConstants.INVALID_STATE_ERROR,
        { errorMsg: JSON.stringify(error) } as WebViewEvalResult,
      );
    }
  }

  override layout(
    x: number,
    y: number,
    width: number,
    height: number,
    _paddingLeft: number,
    _paddingTop: number,
    _paddingRight: number,
    _paddingBottom: number,
    _marginLeft: number,
    _marginTop: number,
    _marginRight: number,
    _marginBottom: number,
    _sticky?: number[],
  ): void {
    this.x = x;
    this.y = y;
    this.width = width;
    this.height = height;
  }

  override dispose(): void {
    this.controllerAttached = false;
    super.dispose();
  }
}
