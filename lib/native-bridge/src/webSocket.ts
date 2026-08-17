/**
 * App-owned WebSocket contract shared by every Lynx bundle.
 *
 * The transport is implemented by each native host and intentionally does not
 * depend on Lynx DevTool's private WebSocket module.
 */
import { NATIVE_MODULE_NAMES } from '@lynx-app/native-contracts';
import { requireNativeModule } from './moduleRegistry.js';

export type WebSocketDataType = 'text' | 'base64';
export type WebSocketEventType = 'open' | 'message' | 'error' | 'close';

export interface WebSocketOptions {
  url: string;
  protocols?: string[];
  headers?: Record<string, string>;
}

export interface WebSocketOpenEvent {
  type: 'open';
  protocol: string;
}

export interface WebSocketMessageEvent {
  type: 'message';
  data: string;
  dataType: WebSocketDataType;
}

export interface WebSocketErrorEvent {
  type: 'error';
  message: string;
}

export interface WebSocketCloseEvent {
  type: 'close';
  code: number;
  reason: string;
  wasClean: boolean;
}

export interface WebSocketEventMap {
  open: WebSocketOpenEvent;
  message: WebSocketMessageEvent;
  error: WebSocketErrorEvent;
  close: WebSocketCloseEvent;
}

interface WebSocketEventPayload {
  id?: unknown;
  type?: unknown;
  protocol?: unknown;
  data?: unknown;
  dataType?: unknown;
  message?: unknown;
  code?: unknown;
  reason?: unknown;
  wasClean?: unknown;
}

type WebSocketListener<T extends WebSocketEventType> = (
  event: WebSocketEventMap[T],
) => void;

type UntypedWebSocketListener = (
  event: WebSocketEventMap[WebSocketEventType],
) => void;

export const WEBSOCKET_EVENT = 'webSocket';

const connections = new Map<string, WebSocketConnection>();
let nextConnectionID = 0;
let listeningForEvents = false;

function requireWebSocketModule() {
  'background only';
  return requireNativeModule(NATIVE_MODULE_NAMES.WebSocket);
}

function invoke(
  action: (callback: (error: string) => void) => void,
): Promise<void> {
  'background only';
  return new Promise((resolve, reject) => {
    try {
      action((error) => {
        if (error.length > 0) {
          reject(new Error(error));
        } else {
          resolve();
        }
      });
    } catch (error) {
      reject(error instanceof Error ? error : new Error(String(error)));
    }
  });
}

function installEventListener(): void {
  'background only';
  if (listeningForEvents) return;
  listeningForEvents = true;
  lynx
    .getJSModule('GlobalEventEmitter')
    .addListener(WEBSOCKET_EVENT, dispatchEvent);
}

function dispatchEvent(value: unknown): void {
  'background only';
  if (typeof value !== 'object' || value === null) return;
  const payload = value as WebSocketEventPayload;
  if (typeof payload.id !== 'string') return;
  connections.get(payload.id)?.receiveEvent(payload);
}

function normalizedOptions(
  options: WebSocketOptions,
): Required<WebSocketOptions> {
  'background only';
  return {
    url: options.url,
    protocols: [...(options.protocols ?? [])],
    headers: { ...(options.headers ?? {}) },
  };
}

/** A browser-shaped, app-owned WebSocket connection for Lynx background JS. */
export class WebSocketConnection {
  static readonly CONNECTING = 0;
  static readonly OPEN = 1;
  static readonly CLOSING = 2;
  static readonly CLOSED = 3;

  readonly id: string;
  readonly url: string;
  readonly opened: Promise<void>;
  readonly closed: Promise<WebSocketCloseEvent>;

  readyState = WebSocketConnection.CONNECTING;
  protocol = '';

  private readonly options: Required<WebSocketOptions>;
  private readonly listeners: Map<
    WebSocketEventType,
    Set<UntypedWebSocketListener>
  > = new Map();
  private resolveOpened: () => void = () => {};
  private rejectOpened: (error: Error) => void = () => {};
  private resolveClosed: (event: WebSocketCloseEvent) => void = () => {};
  private openSettled = false;

  constructor(options: WebSocketOptions) {
    this.options = normalizedOptions(options);
    this.url = this.options.url;
    nextConnectionID += 1;
    this.id = `ws-${Date.now().toString(36)}-${nextConnectionID.toString(36)}`;
    this.opened = new Promise((resolve, reject) => {
      this.resolveOpened = resolve;
      this.rejectOpened = reject;
    });
    this.closed = new Promise((resolve) => {
      this.resolveClosed = resolve;
    });

    installEventListener();
    connections.set(this.id, this);
    void invoke((callback) =>
      requireWebSocketModule().connect(
        {
          id: this.id,
          url: this.options.url,
          protocols: this.options.protocols,
          headers: this.options.headers,
        },
        callback,
      ),
    ).catch((error: Error) => this.failToStart(error));
  }

  addEventListener<T extends WebSocketEventType>(
    type: T,
    listener: WebSocketListener<T>,
  ): () => void {
    'background only';
    const listeners = this.listeners.get(type) ?? new Set();
    listeners.add(listener as UntypedWebSocketListener);
    this.listeners.set(type, listeners);
    return () => {
      'background only';
      this.removeEventListener(type, listener);
    };
  }

  removeEventListener<T extends WebSocketEventType>(
    type: T,
    listener: WebSocketListener<T>,
  ): void {
    'background only';
    this.listeners.get(type)?.delete(listener as UntypedWebSocketListener);
  }

  send(data: string): Promise<void> {
    'background only';
    if (this.readyState !== WebSocketConnection.OPEN) {
      return Promise.reject(new Error('WebSocket is not open'));
    }
    return invoke((callback) =>
      requireWebSocketModule().sendText(this.id, data, callback),
    );
  }

  /** Sends binary bytes encoded as standard Base64 across the native bridge. */
  sendBase64(data: string): Promise<void> {
    'background only';
    if (this.readyState !== WebSocketConnection.OPEN) {
      return Promise.reject(new Error('WebSocket is not open'));
    }
    return invoke((callback) =>
      requireWebSocketModule().sendBase64(this.id, data, callback),
    );
  }

  async close(code = 1000, reason = ''): Promise<WebSocketCloseEvent> {
    'background only';
    if (this.readyState === WebSocketConnection.CLOSED) return this.closed;
    if (this.readyState === WebSocketConnection.CLOSING) return this.closed;

    const previousState = this.readyState;
    this.readyState = WebSocketConnection.CLOSING;
    try {
      await invoke((callback) =>
        requireWebSocketModule().close(this.id, code, reason, callback),
      );
    } catch (error) {
      this.readyState = previousState;
      throw error;
    }
    return this.closed;
  }

  /** @internal Called only by the shared native event dispatcher. */
  receiveEvent(payload: WebSocketEventPayload): void {
    'background only';
    switch (payload.type) {
      case 'open': {
        if (this.readyState !== WebSocketConnection.CONNECTING) return;
        this.readyState = WebSocketConnection.OPEN;
        this.protocol =
          typeof payload.protocol === 'string' ? payload.protocol : '';
        this.openSettled = true;
        this.resolveOpened();
        this.emit({ type: 'open', protocol: this.protocol });
        break;
      }
      case 'message': {
        if (
          this.readyState !== WebSocketConnection.OPEN ||
          typeof payload.data !== 'string' ||
          (payload.dataType !== 'text' && payload.dataType !== 'base64')
        ) {
          return;
        }
        this.emit({
          type: 'message',
          data: payload.data,
          dataType: payload.dataType,
        });
        break;
      }
      case 'error': {
        const event: WebSocketErrorEvent = {
          type: 'error',
          message:
            typeof payload.message === 'string'
              ? payload.message
              : 'Unknown WebSocket error',
        };
        if (!this.openSettled) {
          this.openSettled = true;
          this.rejectOpened(new Error(event.message));
        }
        this.emit(event);
        break;
      }
      case 'close': {
        if (this.readyState === WebSocketConnection.CLOSED) return;
        const event: WebSocketCloseEvent = {
          type: 'close',
          code: typeof payload.code === 'number' ? payload.code : 1006,
          reason: typeof payload.reason === 'string' ? payload.reason : '',
          wasClean: typeof payload.wasClean === 'boolean' && payload.wasClean,
        };
        this.readyState = WebSocketConnection.CLOSED;
        if (!this.openSettled) {
          this.openSettled = true;
          this.rejectOpened(
            new Error(
              event.reason || `WebSocket closed with code ${event.code}`,
            ),
          );
        }
        connections.delete(this.id);
        this.resolveClosed(event);
        this.emit(event);
        this.listeners.clear();
        break;
      }
    }
  }

  private failToStart(error: Error): void {
    'background only';
    this.receiveEvent({
      id: this.id,
      type: 'error',
      message: error.message,
    });
    this.receiveEvent({
      id: this.id,
      type: 'close',
      code: 1006,
      reason: error.message,
      wasClean: false,
    });
  }

  private emit<T extends WebSocketEventType>(
    event: WebSocketEventMap[T],
  ): void {
    'background only';
    const listeners = this.listeners.get(event.type);
    if (listeners === undefined) return;
    for (const listener of [...listeners]) {
      try {
        listener(event);
      } catch (error) {
        console.error(
          `WebSocketConnection ${event.type} listener failed: ${String(error)}`,
        );
      }
    }
  }
}

export const webSocket = {
  connect(options: WebSocketOptions): WebSocketConnection {
    'background only';
    return new WebSocketConnection(options);
  },
};
