import { connection } from '@kit.NetworkKit';
import { LynxContext, LynxModule, LynxViewClient } from '@lynx/lynx';

class NetworkInfoEventPayload {
  connected: boolean = false;
  type: string = 'unknown';
  cellularGeneration: string | null = null;
  timestamp: number = 0;
  error: string = '';
}

class NetworkInfoValue {
  connected: boolean;
  type: string;
  cellularGeneration: string | null;
  timestamp: number;

  constructor(connected: boolean, type: string, cellularGeneration: string | null) {
    this.connected = connected;
    this.type = type;
    this.cellularGeneration = cellularGeneration;
    this.timestamp = Date.now();
  }
}

class NetworkInfoResult {
  value: NetworkInfoValue | null;
  error: string;

  constructor(value: NetworkInfoValue | null, error: string = '') {
    this.value = value;
    this.error = error;
  }
}

// connection.NetBearType values used to classify the default network.
const BEARER_CELLULAR: number = 0;
const BEARER_WIFI: number = 1;
const BEARER_ETHERNET: number = 3;
// connection.NetCap.NET_CAPABILITY_INTERNET.
const NET_CAPABILITY_INTERNET: number = 12;

/** Owns the NetConnection subscription created by one module instance. */
class NativeNetworkInfoController {
  private context: LynxContext | undefined = undefined;
  private destroyed: boolean = false;
  private netConnection: connection.NetConnection | undefined = undefined;
  private listening: boolean = false;
  private lastEmittedSignature: string = '';

  getInfo(callback: (resultJSON: string) => void): void {
    try {
      callback(JSON.stringify(new NetworkInfoResult(this.snapshot())));
    } catch (error) {
      callback(JSON.stringify(new NetworkInfoResult(
        null, this.messageOf(error, 'Unable to read the network state'))));
    }
  }

  start(callback: (error: string) => void, context: LynxContext): void {
    this.destroyed = false;
    this.context = context;
    if (this.listening) {
      callback('');
      return;
    }
    try {
      if (this.netConnection === undefined) {
        this.netConnection = connection.createNetConnection();
      }
      const netConnection = this.netConnection;
      netConnection.register((error) => {
        if (error !== undefined && error.code !== undefined && error.code !== 0) {
          this.emitError(this.messageOf(error, 'Unable to listen for network changes'));
          return;
        }
        netConnection.on('netAvailable', () => this.emitSnapshot());
        netConnection.on('netCapabilitiesChange', () => this.emitSnapshot());
        netConnection.on('netLost', () => this.emitSnapshot());
        netConnection.on('netUnavailable', () => this.emitSnapshot());
        // Observers always start with the current state; later updates
        // arrive through the callbacks above.
        this.emitSnapshot();
      });
      this.listening = true;
      callback('');
    } catch (error) {
      callback(this.messageOf(error, 'Unable to listen for network changes'));
    }
  }

  stop(callback: (error: string) => void): void {
    this.stopListening();
    callback('');
  }

  destroy(): void {
    this.destroyed = true;
    this.stopListening();
    this.context = undefined;
  }

  private stopListening(): void {
    const netConnection = this.netConnection;
    this.netConnection = undefined;
    this.listening = false;
    this.lastEmittedSignature = '';
    if (netConnection !== undefined) {
      try {
        netConnection.unregister(() => {
        });
      } catch (_error) {
      }
    }
  }

  private snapshot(): NetworkInfoValue {
    const handles = connection.getAllNetsSync();
    if (handles.length === 0) {
      return new NetworkInfoValue(false, 'none', null);
    }
    const capabilities = connection.getNetCapabilitiesSync(handles[0]);
    const bearers = capabilities.bearerTypes;
    if (bearers.includes(BEARER_WIFI)) {
      return new NetworkInfoValue(true, 'wifi', null);
    }
    if (bearers.includes(BEARER_CELLULAR)) {
      // HarmonyOS exposes no permission-free radio generation, so the
      // cellular generation is always null here.
      return new NetworkInfoValue(true, 'cellular', null);
    }
    if (bearers.includes(BEARER_ETHERNET)) {
      return new NetworkInfoValue(true, 'ethernet', null);
    }
    const netCaps = capabilities.networkCap;
    const connected = netCaps !== undefined && netCaps.includes(NET_CAPABILITY_INTERNET);
    return new NetworkInfoValue(connected, 'other', null);
  }

  private emitSnapshot(): void {
    if (this.destroyed) {
      return;
    }
    try {
      const value = this.snapshot();
      const payload = new NetworkInfoEventPayload();
      payload.connected = value.connected;
      payload.type = value.type;
      payload.cellularGeneration = value.cellularGeneration;
      payload.timestamp = value.timestamp;
      // Capability callbacks also fire for signal-strength changes;
      // observers only care about material transitions.
      const signature = `${value.connected}|${value.type}|${value.cellularGeneration ?? ''}`;
      if (signature === this.lastEmittedSignature) {
        return;
      }
      this.lastEmittedSignature = signature;
      this.emit(payload);
    } catch (error) {
      this.emitError(this.messageOf(error, 'Unable to read the network state'));
    }
  }

  private emitError(message: string): void {
    const payload = new NetworkInfoEventPayload();
    payload.error = message;
    this.emit(payload);
  }

  private emit(payload: NetworkInfoEventPayload): void {
    if (!this.destroyed) {
      this.context?.sendGlobalEvent(NetworkInfoModule.EVENT_NAME, [payload]);
    }
  }

  private messageOf(error: Object, fallback: string): string {
    return error instanceof Error && error.message.length > 0 ? error.message : fallback;
  }
}

class NetworkInfoLifecycleClient extends LynxViewClient {
  private readonly controller: NativeNetworkInfoController;

  constructor(controller: NativeNetworkInfoController) {
    super();
    this.controller = controller;
  }

  override onDestroy(): void {
    this.controller.destroy();
  }
}

/** HarmonyOS network reachability exported to Lynx as NetworkInfo. */
export class NetworkInfoModule extends LynxModule {
  static readonly NAME: string = 'NetworkInfo';
  static readonly EVENT_NAME: string = 'networkInfo';
  private readonly controller: NativeNetworkInfoController;

  constructor(context: LynxContext, param?: Object) {
    super(context, param);
    this.controller = new NativeNetworkInfoController();
    context.getLynxViewClient()?.push(new NetworkInfoLifecycleClient(this.controller));
  }

  getInfo(callback: (resultJSON: string) => void): void {
    this.controller.getInfo(callback);
  }

  start(callback: (error: string) => void): void {
    this.controller.start(callback, this.context);
  }

  stop(callback: (error: string) => void): void {
    this.controller.stop(callback);
  }
}
