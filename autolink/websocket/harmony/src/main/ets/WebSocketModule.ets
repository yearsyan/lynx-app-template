import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { webSocket } from '@kit.NetworkKit';
import { LynxContext, LynxModule, LynxViewClient } from '@lynx/lynx';
import BuildProfile from 'BuildProfile';

export interface NativeWebSocketOptions {
  id: string;
  url: string;
  protocols: string[];
  headers: Record<string, string>;
}

class NativeWebSocketEventPayload {
  id: string;
  type: string;
  protocol: string = '';
  data: string = '';
  dataType: string = '';
  message: string = '';
  code: number = 0;
  reason: string = '';
  wasClean: boolean = false;

  constructor(id: string, type: string) {
    this.id = id;
    this.type = type;
  }
}

class NativeWebSocketConnection {
  readonly id: string;
  readonly socket: webSocket.WebSocket;
  readonly context: LynxContext;
  open: boolean = false;
  terminal: boolean = false;

  constructor(id: string, socket: webSocket.WebSocket, context: LynxContext) {
    this.id = id;
    this.socket = socket;
    this.context = context;
  }
}

/** Owns the connections created by one Lynx NativeModule instance. */
class NativeWebSocketController {
  private readonly connections: Map<string, NativeWebSocketConnection> = new Map();
  private readonly base64: util.Base64Helper = new util.Base64Helper();
  private destroyed: boolean = false;

  connect(options: NativeWebSocketOptions, context: LynxContext): string {
    this.destroyed = false;
    if (!new RegExp('^[A-Za-z0-9._-]{1,128}$').test(options.id)) {
      return 'Invalid WebSocket connection ID';
    }
    if (!this.isAllowedURL(options.url)) {
      return 'WebSocket URL must use wss:// (ws:// is Debug-only)';
    }
    if (this.connections.has(options.id)) {
      return 'WebSocket connection ID already exists';
    }

    const socket = webSocket.createWebSocket();
    const connection = new NativeWebSocketConnection(options.id, socket, context);
    this.connections.set(options.id, connection);
    this.installListeners(connection);

    const headers: Record<string, string> = {};
    const headerNames = Object.keys(options.headers);
    for (let index = 0; index < headerNames.length; index++) {
      const name = headerNames[index];
      headers[name] = options.headers[name];
    }
    if (options.protocols.length > 0) {
      headers['Sec-WebSocket-Protocol'] = options.protocols.join(', ');
    }

    try {
      socket.connect(options.url, { header: headers }).then((accepted: boolean) => {
        if (!accepted) {
          this.fail(connection, 'WebSocket connection request was rejected');
        }
      }).catch((error: Error) => {
        this.fail(connection, error.message);
      });
    } catch (error) {
      this.connections.delete(options.id);
      this.removeListeners(connection);
      return `Unable to create WebSocket: ${JSON.stringify(error)}`;
    }
    return '';
  }

  sendText(id: string, data: string, callback: (error: string) => void): void {
    const connection = this.connections.get(id);
    if (connection === undefined || !connection.open || connection.terminal) {
      callback('WebSocket is not open');
      return;
    }
    this.send(connection, data, callback);
  }

  sendBase64(id: string, data: string, callback: (error: string) => void): void {
    const connection = this.connections.get(id);
    if (connection === undefined || !connection.open || connection.terminal) {
      callback('WebSocket is not open');
      return;
    }
    try {
      const bytes = this.base64.decodeSync(data);
      const payload = new ArrayBuffer(bytes.byteLength);
      new Uint8Array(payload).set(bytes);
      this.send(connection, payload, callback);
    } catch (error) {
      callback('Invalid Base64 WebSocket payload');
    }
  }

  close(id: string, code: number, reason: string, callback: (error: string) => void): void {
    const connection = this.connections.get(id);
    if (connection === undefined || connection.terminal) {
      callback('Unknown WebSocket connection ID');
      return;
    }
    connection.socket.close({ code, reason }).then((accepted: boolean) => {
      callback(accepted ? '' : 'WebSocket close request was rejected');
    }).catch((error: Error) => {
      callback(error.message);
    });
  }

  destroy(): void {
    this.destroyed = true;
    const connections = Array.from(this.connections.values());
    this.connections.clear();
    for (let index = 0; index < connections.length; index++) {
      const connection = connections[index];
      connection.terminal = true;
      this.removeListeners(connection);
      connection.socket.close({ code: 1001, reason: 'Lynx page destroyed' }).catch(() => {});
    }
  }

  private installListeners(connection: NativeWebSocketConnection): void {
    connection.socket.on('open', (error: BusinessError, _value: Object) => {
      if (error) {
        this.fail(connection, error.message);
        return;
      }
      if (connection.terminal || this.destroyed) {
        return;
      }
      connection.open = true;
      const payload = new NativeWebSocketEventPayload(connection.id, 'open');
      connection.context.sendGlobalEvent(WebSocketModule.EVENT_NAME, [payload]);
    });
    connection.socket.on('message', (error: BusinessError, value: string | ArrayBuffer) => {
      if (error) {
        this.fail(connection, error.message);
        return;
      }
      if (connection.terminal || this.destroyed) {
        return;
      }
      const payload = new NativeWebSocketEventPayload(connection.id, 'message');
      if (typeof value === 'string') {
        payload.dataType = 'text';
        payload.data = value;
      } else {
        payload.dataType = 'base64';
        payload.data = this.base64.encodeToStringSync(new Uint8Array(value));
      }
      connection.context.sendGlobalEvent(WebSocketModule.EVENT_NAME, [payload]);
    });
    connection.socket.on('close', (error: BusinessError, result: webSocket.CloseResult) => {
      if (error) {
        this.fail(connection, error.message);
        return;
      }
      this.finish(connection, result.code, result.reason, true);
    });
    connection.socket.on('error', (error: BusinessError) => {
      this.fail(connection, error.message);
    });
  }

  private removeListeners(connection: NativeWebSocketConnection): void {
    connection.socket.off('open');
    connection.socket.off('message');
    connection.socket.off('close');
    connection.socket.off('error');
  }

  private send(
    connection: NativeWebSocketConnection,
    data: string | ArrayBuffer,
    callback: (error: string) => void,
  ): void {
    connection.socket.send(data).then((accepted: boolean) => {
      callback(accepted ? '' : 'WebSocket send queue rejected the message');
    }).catch((error: Error) => {
      callback(error.message);
    });
  }

  private fail(connection: NativeWebSocketConnection, message: string): void {
    if (!this.take(connection)) {
      return;
    }
    const errorPayload = new NativeWebSocketEventPayload(connection.id, 'error');
    errorPayload.message = message.length > 0 ? message : 'WebSocket transport failed';
    connection.context.sendGlobalEvent(WebSocketModule.EVENT_NAME, [errorPayload]);
    this.emitClose(connection, 1006, errorPayload.message, false);
  }

  private finish(
    connection: NativeWebSocketConnection,
    code: number,
    reason: string,
    wasClean: boolean,
  ): void {
    if (this.take(connection)) {
      this.emitClose(connection, code, reason, wasClean);
    }
  }

  private take(connection: NativeWebSocketConnection): boolean {
    if (connection.terminal || this.destroyed || this.connections.get(connection.id) !== connection) {
      return false;
    }
    connection.terminal = true;
    this.connections.delete(connection.id);
    this.removeListeners(connection);
    return true;
  }

  private emitClose(
    connection: NativeWebSocketConnection,
    code: number,
    reason: string,
    wasClean: boolean,
  ): void {
    const payload = new NativeWebSocketEventPayload(connection.id, 'close');
    payload.code = code;
    payload.reason = reason;
    payload.wasClean = wasClean;
    connection.context.sendGlobalEvent(WebSocketModule.EVENT_NAME, [payload]);
  }

  private isAllowedURL(value: string): boolean {
    return new RegExp('^wss://[^\\s]+$', 'i').test(value) ||
      (BuildProfile.DEBUG && new RegExp('^ws://[^\\s]+$', 'i').test(value));
  }
}

class WebSocketLifecycleClient extends LynxViewClient {
  private readonly controller: NativeWebSocketController;

  constructor(controller: NativeWebSocketController) {
    super();
    this.controller = controller;
  }

  override onDestroy(): void {
    this.controller.destroy();
  }
}

/** Production WebSocket transport exported to Lynx as WebSocket. */
export class WebSocketModule extends LynxModule {
  static readonly NAME: string = 'WebSocket';
  static readonly EVENT_NAME: string = 'webSocket';
  private readonly controller: NativeWebSocketController;

  constructor(context: LynxContext, param?: Object) {
    super(context, param);
    this.controller = new NativeWebSocketController();
    context.getLynxViewClient()?.push(new WebSocketLifecycleClient(this.controller));
  }

  connect(options: NativeWebSocketOptions, callback: (error: string) => void): void {
    callback(this.controller.connect(options, this.context));
  }

  sendText(id: string, data: string, callback: (error: string) => void): void {
    this.controller.sendText(id, data, callback);
  }

  sendBase64(id: string, data: string, callback: (error: string) => void): void {
    this.controller.sendBase64(id, data, callback);
  }

  close(id: string, code: number, reason: string, callback: (error: string) => void): void {
    this.controller.close(id, code, reason, callback);
  }
}
