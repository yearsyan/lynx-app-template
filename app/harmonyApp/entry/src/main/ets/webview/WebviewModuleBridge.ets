// Explicit HarmonyOS host adapter for Lynx <module-webview> elements.
//
// The stock @lynx/lynx SDK ships no webview behavior on this platform, so
// this file provides both halves of Route B:
//   1. a `module-webview` behavior whose UIBase renders an ArkUI Web component, and
//   2. a JS bridge (window.__lynxNativeBridge, same wire protocol as the
//      Android and iOS hosts) that reuses the module registry this LynxView
//      can reach — the global Autolink registry overlaid with the page map —
//      to dispatch page calls to the same native modules the template reaches
//      through NativeModules.
//
// Page JS only gets access to modules explicitly listed by the element's
// params['module-bridge'].modules capability list. Calls inject the module's
// trailing callback argument and resolve the Promise with its result.
import { webview } from '@kit.ArkWeb';
import { BusinessError } from '@kit.BasicServicesKit';
import {
  Behavior,
  IContext,
  LynxContext,
  LynxModule,
  LynxModuleManager,
  ModuleClassWrapper,
  UIBase,
} from '@lynx/lynx';
import { collectGlobalModules } from '@lynx/lynx_autolink_registry';

import { nativeModuleMethodArity } from '../contracts/NativeModuleContracts';

/**
 * Shared per-LynxView host state: the module registry to reuse. LynxView
 * resolves a module from the global Autolink registry first and the page map
 * second, so the adapter mirrors that order — page entries win over global
 * ones (the page-scoped DeviceInfo registration carries host state).
 */
export class WebviewModuleBridgeHostAdapter {
  readonly modules: Map<string, ModuleClassWrapper>;

  constructor(pageModules: Map<string, ModuleClassWrapper>) {
    this.modules = collectGlobalModules();
    pageModules.forEach((wrapper, name) => {
      this.modules.set(name, wrapper);
    });
  }
}

/** params['module-bridge'] shape accepted by the element. */
export interface WebviewBridgeParams {
  'module-bridge'?: BridgeModuleConfig;
}

interface BridgeModuleConfig {
  modules: string[];
}

/** RPC request envelope posted by the bootstrap script. */
interface BridgeRequest {
  session: string;
  id: number;
  module: string;
  method: string;
  args: Object[];
}

interface BridgeResponse {
  session: string;
  id: number;
  ok: boolean;
  result?: Object[];
  error?: string;
}

/** Event detail shapes for bindload / binderror. */
class WebviewLoadDetail {
}

class WebviewErrorDetail {
  errorCode: number = 0;
  errorMsg: string = '';
}

/** Casting vehicle for a module method looked up by name at runtime. */
interface FunctionLike {
  length: number;
  bind(self: Object): Function;
}

class NativeTransport {
  private readonly ui: ModuleWebviewUI;

  constructor(ui: ModuleWebviewUI) {
    this.ui = ui;
  }

  invokeNative(request: string): void {
    this.ui.handleInvoke(request);
  }
}

const PROXY_NAME: string = 'lynxNativeTransport';
const JS_API_NAME: string = '__lynxNativeBridge';
const ABOUT_BLANK: string = 'about:blank';
const BLOCKED_MODULES: string[] = ['AppInstaller'];

const BOOTSTRAP_SCRIPT: string = `
(function () {
  if (window.__lynxNativeBridge) { return; }
  var session = 'wv-' + Date.now().toString(36) + '-' + Math.random().toString(36).slice(2);
  var nextId = 1;
  var pending = Object.create(null);
  function settle(envelope) {
    if (!envelope || envelope.session !== session) { return; }
    var entry = pending[envelope.id];
    if (!entry) { return; }
    delete pending[envelope.id];
    if (envelope.ok) {
      entry.resolve(envelope.result || []);
    } else {
      entry.reject(new Error(envelope.error || 'invoke failed'));
    }
  }
  window.__lynxNativeBridge = {
    invoke: function (moduleName, methodName, args) {
      var id = nextId++;
      return new Promise(function (resolve, reject) {
        pending[id] = { resolve: resolve, reject: reject };
        lynxNativeTransport.invokeNative(
          JSON.stringify({
            session: session,
            id: id,
            module: moduleName,
            method: methodName,
            args: args || []
          })
        );
      });
    },
    _onResponse: settle
  };
  window.dispatchEvent(new Event('lynx-native-bridge-ready'));
})();
`;

@Builder
function buildWebview(ui: UIBase) {
  Web({ controller: (ui as ModuleWebviewUI).controller, src: ABOUT_BLANK })
    .width('100%')
    .height('100%')
    .javaScriptAccess(true)
    .domStorageAccess(true)
    .zoomAccess(false)
    .javaScriptOnDocumentStart([{ script: BOOTSTRAP_SCRIPT, scriptRules: ['*'] }])
    .onControllerAttached(() => {
      (ui as ModuleWebviewUI).onControllerAttached();
    })
    .onPageEnd((event: OnPageEndEvent) => {
      (ui as ModuleWebviewUI).onPageEnd(event.url);
    })
    .onErrorReceive((event: OnErrorReceiveEvent) => {
      if (event.request.isMainFrame()) {
        (ui as ModuleWebviewUI).onMainFrameError(
          event.error.getErrorCode(),
          event.error.getErrorInfo(),
        );
      }
    });
}

/**
 * Renders `<module-webview>` elements and dispatches page calls into the host's
 * native modules. One instance per element; module instances are cached
 * per element like on the other platforms.
 */
export class ModuleWebviewUI extends UIBase {
  readonly controller: webview.WebviewController = new webview.WebviewController();
  private readonly host: WebviewModuleBridgeHostAdapter;
  private manager: LynxModuleManager | undefined = undefined;
  private src: string = '';
  private html: string = '';
  private allowedModules: string[] = [];
  private controllerAttached: boolean = false;
  private initialDocumentReady: boolean = false;
  private proxyRegistered: boolean = false;

  constructor(context: IContext, param?: Object) {
    super(context, param);
    this.host = param as WebviewModuleBridgeHostAdapter;
    this.builder = wrapBuilder(buildWebview);
  }

  /** The ArkUI Web fills the BuilderNode; no manual layout is needed. */
  layout(x: number, y: number, width: number, height: number, paddingLeft: number,
    paddingTop: number, paddingRight: number, paddingBottom: number, marginLeft: number, marginTop: number,
    marginRight: number, marginBottom: number, sticky?: number[]): void {
  }

  update(props: Object): void {
    const record = props as Record<string, Object>;
    const params = record['params'] as Record<string, Object> | undefined;
    const bridge = params?.['module-bridge'] as Record<string, Object> | undefined;
    this.allowedModules = [];
    const modules = bridge?.['modules'];
    if (Array.isArray(modules)) {
      this.allowedModules = (modules as string[])
        .filter((moduleName: string) => !BLOCKED_MODULES.includes(moduleName));
    }
    const nextSrc = record['src'];
    if (typeof nextSrc === 'string' && nextSrc.length > 0) {
      this.html = '';
      if (nextSrc !== this.src) {
        this.src = nextSrc;
        this.loadPending();
      }
    }
    const nextHtml = record['html'];
    if (typeof nextHtml === 'string' && nextHtml.length > 0 && this.src.length === 0) {
      if (nextHtml !== this.html) {
        this.html = nextHtml;
        this.loadPending();
      }
    }
  }

  invokeMethod(
    method: string,
    params: Object,
    callback: (code: number, res: Object) => void,
  ): boolean {
    if (method === 'reload') {
      this.controller.refresh();
      callback(0, '');
      return true;
    }
    if (method === 'eval') {
      const func = (params as Record<string, Object>)['func'];
      if (typeof func !== 'string' || func.length === 0) {
        callback(4, 'invalid func');
        return true;
      }
      this.controller.runJavaScript(func)
        .then(() => callback(0, ''))
        .catch((error: BusinessError<void>) => callback(8, error.message));
      return true;
    }
    return false;
  }

  onControllerAttached(): void {
    if (!this.proxyRegistered) {
      this.controller.registerJavaScriptProxy(
        new NativeTransport(this),
        PROXY_NAME,
        ['invokeNative'],
      );
      this.proxyRegistered = true;
    }
    this.controllerAttached = true;
  }

  onPageEnd(url: string): void {
    // ArkUI starts the declarative `src: about:blank` load after attaching the
    // controller. Starting loadData/loadUrl from onControllerAttached races
    // with that load and ArkWeb aborts the requested document. Let the initial
    // document finish once, then hand navigation ownership to the adapter.
    if (!this.initialDocumentReady) {
      this.initialDocumentReady = true;
      this.loadPending();
      return;
    }
    this.sendEvent('load', new WebviewLoadDetail());
  }

  onMainFrameError(code: number, message: string): void {
    const detail = new WebviewErrorDetail();
    detail.errorCode = code;
    detail.errorMsg = message;
    this.sendEvent('error', detail);
  }

  dispose(): void {
    this.manager = undefined;
    super.dispose();
  }

  private loadPending(): void {
    if (!this.controllerAttached || !this.initialDocumentReady) {
      return;
    }
    try {
      if (this.src.length > 0) {
        this.controller.loadUrl(this.src);
      } else if (this.html.length > 0) {
        // ArkWeb builds a data: URL from this argument and requires URL- or
        // Base64-encoded input. Raw HTML is truncated at characters such as
        // the `#` in CSS colors, leaving an apparently successful blank page.
        this.controller.loadData(encodeURIComponent(this.html), 'text/html', 'UTF-8');
      }
    } catch (error) {
      this.onMainFrameError(-1, `${error}`);
    }
  }

  private sendEvent(name: string, detail: Object): void {
    this.lynxContext.sendCustomEvent(name, this.sign!, detail);
  }

  handleInvoke(request: string): void {
    let parsed: BridgeRequest;
    try {
      parsed = JSON.parse(request) as BridgeRequest;
    } catch (error) {
      return;
    }
    if (typeof parsed.id !== 'number') {
      return;
    }
    const callId = parsed.id;
    const session = String(parsed.session ?? '');
    const moduleName = String(parsed.module ?? '');
    const methodName = String(parsed.method ?? '');
    const args = Array.isArray(parsed.args) ? parsed.args : [];

    if (session.length === 0 || moduleName.length === 0 || methodName.length === 0) {
      return;
    }
    if (BLOCKED_MODULES.includes(moduleName)) {
      this.respond({
        session,
        id: callId,
        ok: false,
        error: `module '${moduleName}' is blocked from webviews`,
      });
      return;
    }
    if (!this.allowedModules.includes(moduleName)) {
      this.respond({
        session,
        id: callId,
        ok: false,
        error: `module '${moduleName}' is not exposed to this webview`,
      });
      return;
    }
    const wrapper = this.host.modules.get(moduleName);
    if (wrapper === undefined) {
      this.respond({ session, id: callId, ok: false, error: `unknown module '${moduleName}'` });
      return;
    }
    try {
      this.invokeModule(session, callId, moduleName, wrapper, methodName, args);
    } catch (error) {
      this.respond({ session, id: callId, ok: false, error: `${error}` });
    }
  }

  private invokeModule(
    session: string,
    callId: number,
    moduleName: string,
    wrapper: ModuleClassWrapper,
    methodName: string,
    args: Object[],
  ): void {
    const contractArity = nativeModuleMethodArity(moduleName, methodName);
    if (contractArity < 1) {
      this.respond({
        session,
        id: callId,
        ok: false,
        error: `module has no exported method '${methodName}'`,
      });
      return;
    }
    const instance = this.moduleInstance(moduleName, wrapper);
    const instanceRecord = instance as Object as Record<string, Object>;
    const method = instanceRecord[methodName];
    if (typeof method !== 'function') {
      this.respond({
        session,
        id: callId,
        ok: false,
        error: `module implementation has no method '${methodName}'`,
      });
      return;
    }
    const fn = method as Object as FunctionLike;
    // Every Native Module contract method has one trailing callback. Requiring
    // the exact non-callback arity prevents page data occupying that slot.
    const implementationArity = fn.length;
    if (implementationArity !== contractArity) {
      this.respond({
        session,
        id: callId,
        ok: false,
        error: `native contract mismatch for '${moduleName}.${methodName}'`,
      });
      return;
    }
    if (args.length !== contractArity - 1) {
      this.respond({
        session,
        id: callId,
        ok: false,
        error: `expected ${contractArity - 1} arguments, got ${args.length}`,
      });
      return;
    }
    let responded = false;
    const callback = (result: Object): void => {
      if (responded) {
        return;
      }
      responded = true;
      this.respond({ session, id: callId, ok: true, result: [result ?? ''] });
    };
    const callArgs: Object[] = args.slice(0, contractArity - 1);
    callArgs.push(callback as Object);
    const bound: Function = fn.bind(instance);
    switch (callArgs.length) {
      case 0:
        (bound as () => void)();
        break;
      case 1:
        (bound as (p0: Object) => void)(callArgs[0] as Object);
        break;
      case 2:
        (bound as (p0: Object, p1: Object) => void)(callArgs[0] as Object, callArgs[1] as Object);
        break;
      case 3:
        (bound as (p0: Object, p1: Object, p2: Object) => void)(
          callArgs[0] as Object, callArgs[1] as Object, callArgs[2] as Object);
        break;
      case 4:
        (bound as (p0: Object, p1: Object, p2: Object, p3: Object) => void)(
          callArgs[0] as Object,
          callArgs[1] as Object,
          callArgs[2] as Object,
          callArgs[3] as Object,
        );
        break;
      case 5:
        (bound as (p0: Object, p1: Object, p2: Object, p3: Object, p4: Object) => void)(
          callArgs[0] as Object,
          callArgs[1] as Object,
          callArgs[2] as Object,
          callArgs[3] as Object,
          callArgs[4] as Object,
        );
        break;
      default:
        throw new Error(`unsupported method arity ${callArgs.length}`);
    }
  }

  /** Reuses the SDK's LynxModuleManager for construction and caching. */
  private moduleInstance(name: string, wrapper: ModuleClassWrapper): LynxModule {
    if (this.manager === undefined) {
      this.manager = new LynxModuleManager(this.lynxContext as LynxContext);
    }
    const existing = this.manager.getModule(name);
    if (existing !== undefined) {
      return existing;
    }
    this.manager.registerModule(name, wrapper);
    return this.manager.getModule(name) as LynxModule;
  }

  private respond(response: BridgeResponse): void {
    const json = JSON.stringify(response);
    try {
      this.controller.runJavaScript(
        `window.${JS_API_NAME}&&window.${JS_API_NAME}._onResponse(${json})`,
      );
    } catch (error) {
      console.error(`[WebviewModuleBridge] respond failed: ${error}`);
    }
  }
}

/** Creates the `module-webview` behavior wired to the page's module registry. */
export function createModuleWebviewBehavior(
  host: WebviewModuleBridgeHostAdapter,
): Behavior {
  return new Behavior(ModuleWebviewUI as Function, undefined, host as Object);
}
