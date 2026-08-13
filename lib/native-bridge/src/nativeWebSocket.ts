/**
 * App-owned WebSocket contract shared by every Lynx bundle.
 *
 * The transport is implemented by each native host and intentionally does not
 * depend on Lynx DevTool's private WebSocket module.
 */

export type NativeWebSocketDataType = 'text' | 'base64';
export type NativeWebSocketEventType = 'open' | 'message' | 'error' | 'close';

export interface NativeWebSocketOptions {
  url: string;
  protocols?: string[];
  headers?: Record<string, string>;
}

export interface NativeWebSocketOpenEvent {
  type: 'open';
  protocol: string;
}

export interface NativeWebSocketMessageEvent {
  type: 'message';
  data: string;
  dataType: NativeWebSocketDataType;
}

export interface NativeWebSocketErrorEvent {
  type: 'error';
  message: string;
}

export interface NativeWebSocketCloseEvent {
  type: 'close';
  code: number;
  reason: string;
  wasClean: boolean;
}

export interface NativeWebSocketEventMap {
  open: NativeWebSocketOpenEvent;
  message: NativeWebSocketMessageEvent;
  error: NativeWebSocketErrorEvent;
  close: NativeWebSocketCloseEvent;
}

interface NativeWebSocketEventPayload {
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

interface NativeWebSocketModule {
  connect(
    options: {
      id: string;
      url: string;
      protocols: string[];
      headers: Record<string, string>;
    },
    callback: (error: string) => void,
  ): void;
  sendText(id: string, data: string, callback: (error: string) => void): void;
  sendBase64(id: string, data: string, callback: (error: string) => void): void;
  close(
    id: string,
    code: number,
    reason: string,
    callback: (error: string) => void,
  ): void;
}

interface TemplateNativeModules {
  NativeWebSocketModule?: NativeWebSocketModule;
}

type NativeWebSocketListener<T extends NativeWebSocketEventType> = (
  event: NativeWebSocketEventMap[T],
) => void;

type UntypedNativeWebSocketListener = (
  event: NativeWebSocketEventMap[NativeWebSocketEventType],
) => void;

export const NATIVE_WEBSOCKET_EVENT = 'nativeWebSocket';

const connections = new Map<string, NativeWebSocket>();
let nextConnectionID = 0;
let listeningForNativeEvents = false;

function requireWebSocketModule(): NativeWebSocketModule {
  'background only';
  const module = (NativeModules as TemplateNativeModules).NativeWebSocketModule;
  if (module === undefined) {
    throw new Error(
      'NativeWebSocketModule is not registered by the native host',
    );
  }
  return module;
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

function installNativeEventListener(): void {
  'background only';
  if (listeningForNativeEvents) return;
  listeningForNativeEvents = true;
  lynx
    .getJSModule('GlobalEventEmitter')
    .addListener(NATIVE_WEBSOCKET_EVENT, dispatchNativeEvent);
}

function dispatchNativeEvent(value: unknown): void {
  'background only';
  if (typeof value !== 'object' || value === null) return;
  const payload = value as NativeWebSocketEventPayload;
  if (typeof payload.id !== 'string') return;
  connections.get(payload.id)?.receiveNativeEvent(payload);
}

function normalizedOptions(
  options: NativeWebSocketOptions,
): Required<NativeWebSocketOptions> {
  'background only';
  const url = options.url.trim();
  if (!/^wss?:\/\/[^\s]+$/i.test(url)) {
    throw new Error('WebSocket URL must use ws:// or wss://');
  }

  const protocols = [...(options.protocols ?? [])];
  const seenProtocols = new Set<string>();
  for (const protocol of protocols) {
    if (!/^[!#$%&'*+\-.^_`|~0-9A-Za-z]+$/.test(protocol)) {
      throw new Error(`Invalid WebSocket subprotocol: ${protocol}`);
    }
    if (seenProtocols.has(protocol)) {
      throw new Error(`Duplicate WebSocket subprotocol: ${protocol}`);
    }
    seenProtocols.add(protocol);
  }

  const headers: Record<string, string> = {};
  const inputHeaders = options.headers ?? {};
  for (const name of Object.keys(inputHeaders)) {
    const value = inputHeaders[name];
    if (value === undefined) continue;
    const normalizedName = name.trim();
    const lowerName = normalizedName.toLowerCase();
    if (!/^[!#$%&'*+\-.^_`|~0-9A-Za-z]+$/.test(normalizedName)) {
      throw new Error(`Invalid WebSocket header name: ${name}`);
    }
    if (
      lowerName === 'connection' ||
      lowerName === 'host' ||
      lowerName === 'upgrade' ||
      lowerName.startsWith('sec-websocket-')
    ) {
      throw new Error(`WebSocket manages the ${normalizedName} header`);
    }
    if (value.includes('\r') || value.includes('\n')) {
      throw new Error(`Invalid WebSocket header value: ${normalizedName}`);
    }
    headers[normalizedName] = value;
  }

  return { url, protocols, headers };
}

function closeCodeIsValid(code: number): boolean {
  'background only';
  return code === 1000 || (code >= 3000 && code <= 4999);
}

function utf8ByteLength(value: string): number {
  'background only';
  let bytes = 0;
  for (let index = 0; index < value.length; index += 1) {
    const code = value.charCodeAt(index);
    if (code < 0x80) {
      bytes += 1;
    } else if (code < 0x800) {
      bytes += 2;
    } else if (code >= 0xd800 && code <= 0xdbff) {
      const next = value.charCodeAt(index + 1);
      if (next >= 0xdc00 && next <= 0xdfff) {
        bytes += 4;
        index += 1;
      } else {
        bytes += 3;
      }
    } else {
      bytes += 3;
    }
  }
  return bytes;
}

/** A browser-shaped, app-owned WebSocket connection for Lynx background JS. */
export class NativeWebSocket {
  static readonly CONNECTING = 0;
  static readonly OPEN = 1;
  static readonly CLOSING = 2;
  static readonly CLOSED = 3;

  readonly id: string;
  readonly url: string;
  readonly opened: Promise<void>;
  readonly closed: Promise<NativeWebSocketCloseEvent>;

  readyState = NativeWebSocket.CONNECTING;
  protocol = '';

  private readonly options: Required<NativeWebSocketOptions>;
  private readonly listeners: Map<
    NativeWebSocketEventType,
    Set<UntypedNativeWebSocketListener>
  > = new Map();
  private resolveOpened: () => void = () => {};
  private rejectOpened: (error: Error) => void = () => {};
  private resolveClosed: (event: NativeWebSocketCloseEvent) => void = () => {};
  private openSettled = false;

  constructor(options: NativeWebSocketOptions) {
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

    installNativeEventListener();
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

  addEventListener<T extends NativeWebSocketEventType>(
    type: T,
    listener: NativeWebSocketListener<T>,
  ): () => void {
    'background only';
    const listeners = this.listeners.get(type) ?? new Set();
    listeners.add(listener as UntypedNativeWebSocketListener);
    this.listeners.set(type, listeners);
    return () => {
      'background only';
      this.removeEventListener(type, listener);
    };
  }

  removeEventListener<T extends NativeWebSocketEventType>(
    type: T,
    listener: NativeWebSocketListener<T>,
  ): void {
    'background only';
    this.listeners
      .get(type)
      ?.delete(listener as UntypedNativeWebSocketListener);
  }

  send(data: string): Promise<void> {
    'background only';
    if (this.readyState !== NativeWebSocket.OPEN) {
      return Promise.reject(new Error('WebSocket is not open'));
    }
    return invoke((callback) =>
      requireWebSocketModule().sendText(this.id, data, callback),
    );
  }

  /** Sends binary bytes encoded as standard Base64 across the native bridge. */
  sendBase64(data: string): Promise<void> {
    'background only';
    if (this.readyState !== NativeWebSocket.OPEN) {
      return Promise.reject(new Error('WebSocket is not open'));
    }
    return invoke((callback) =>
      requireWebSocketModule().sendBase64(this.id, data, callback),
    );
  }

  async close(code = 1000, reason = ''): Promise<NativeWebSocketCloseEvent> {
    'background only';
    if (this.readyState === NativeWebSocket.CLOSED) return this.closed;
    if (this.readyState === NativeWebSocket.CLOSING) return this.closed;
    if (!closeCodeIsValid(code)) {
      throw new Error('Close code must be 1000 or between 3000 and 4999');
    }
    if (utf8ByteLength(reason) > 123) {
      throw new Error('WebSocket close reason must be at most 123 UTF-8 bytes');
    }

    const previousState = this.readyState;
    this.readyState = NativeWebSocket.CLOSING;
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
  receiveNativeEvent(payload: NativeWebSocketEventPayload): void {
    'background only';
    switch (payload.type) {
      case 'open': {
        if (this.readyState !== NativeWebSocket.CONNECTING) return;
        this.readyState = NativeWebSocket.OPEN;
        this.protocol =
          typeof payload.protocol === 'string' ? payload.protocol : '';
        this.openSettled = true;
        this.resolveOpened();
        this.emit({ type: 'open', protocol: this.protocol });
        break;
      }
      case 'message': {
        if (
          this.readyState !== NativeWebSocket.OPEN ||
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
        const event: NativeWebSocketErrorEvent = {
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
        if (this.readyState === NativeWebSocket.CLOSED) return;
        const event: NativeWebSocketCloseEvent = {
          type: 'close',
          code: typeof payload.code === 'number' ? payload.code : 1006,
          reason: typeof payload.reason === 'string' ? payload.reason : '',
          wasClean: typeof payload.wasClean === 'boolean' && payload.wasClean,
        };
        this.readyState = NativeWebSocket.CLOSED;
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
    this.receiveNativeEvent({
      id: this.id,
      type: 'error',
      message: error.message,
    });
    this.receiveNativeEvent({
      id: this.id,
      type: 'close',
      code: 1006,
      reason: error.message,
      wasClean: false,
    });
  }

  private emit<T extends NativeWebSocketEventType>(
    event: NativeWebSocketEventMap[T],
  ): void {
    'background only';
    const listeners = this.listeners.get(event.type);
    if (listeners === undefined) return;
    for (const listener of [...listeners]) {
      try {
        listener(event);
      } catch (error) {
        console.error(
          `NativeWebSocket ${event.type} listener failed: ${String(error)}`,
        );
      }
    }
  }
}

export const nativeWebSocket = {
  connect(options: NativeWebSocketOptions): NativeWebSocket {
    'background only';
    return new NativeWebSocket(options);
  },
};
