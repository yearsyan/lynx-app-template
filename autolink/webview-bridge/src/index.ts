import type { StandardProps } from '@lynx-js/types';

export const MODULE_WEBVIEW_ELEMENT_NAME = 'module-webview';

export interface ModuleBridgeConfig {
  /** Native modules explicitly exposed to this embedded document. */
  modules: string[];
}

export interface ModuleWebviewParams {
  'module-bridge'?: ModuleBridgeConfig;
  [key: string]: unknown;
}

export interface ModuleWebviewLoadEvent {
  type: string;
  detail: Record<string, never>;
}

export interface ModuleWebviewErrorEvent {
  type: string;
  detail: {
    errorCode: number;
    errorMsg: string;
  };
}

export interface ModuleWebviewMessageEvent {
  type: string;
  detail: {
    data?: unknown;
  };
}

export interface ModuleWebviewProps extends StandardProps {
  src?: string;
  html?: string;
  params?: ModuleWebviewParams;
  'webview-type'?: string;
  'enable-debug'?: boolean;
  bindload?: (event: ModuleWebviewLoadEvent) => void;
  binderror?: (event: ModuleWebviewErrorEvent) => void;
  bindmessage?: (event: ModuleWebviewMessageEvent) => void;
}

declare module '@lynx-js/types' {
  interface IntrinsicElements {
    'module-webview': ModuleWebviewProps;
  }
}
