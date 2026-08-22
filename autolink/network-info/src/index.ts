/**
 * Current network reachability from the native NetworkInfo module. Snapshots
 * are produced on demand with `getInfo()` and streamed with `observe()`; both
 * share the same payload shape. Change events arrive through the Lynx
 * GlobalEventEmitter on the `networkInfo` event and the bridge keeps the
 * native listener registered only while at least one observer is attached.
 */
import {
  completeNativeCall,
  decodeNativeEnvelope,
  requireNativeModule,
} from './bridge.generated.js';

export * from './native.generated.js';

/** Transport the device is currently using to reach the internet. */
export type NetworkType =
  | 'wifi'
  | 'cellular'
  | 'ethernet'
  | 'other'
  | 'none'
  | 'unknown';

/** Cellular radio generation when the platform reports it. */
export type CellularGeneration = '2g' | '3g' | '4g' | '5g';

export interface NetworkInfoSnapshot {
  /** Whether any network transport is currently available. */
  connected: boolean;
  type: NetworkType;
  /**
   * Cellular generation when `type` is `'cellular'` and the platform exposes
   * it without extra permissions; `null` otherwise. Android reports it only
   * when the host holds READ_PHONE_STATE, iOS only on devices with a modem.
   */
  cellularGeneration: CellularGeneration | null;
  /** Snapshot emit time, epoch milliseconds. */
  timestamp: number;
}

interface NetworkInfoEventPayload {
  connected?: unknown;
  type?: unknown;
  cellularGeneration?: unknown;
  timestamp?: unknown;
  error?: unknown;
}

interface NetworkInfoListener {
  onChange: (snapshot: NetworkInfoSnapshot) => void;
  onError?: (message: string) => void;
}

interface NetworkInfoValueResult {
  error?: unknown;
  value?: unknown;
}

export const NETWORK_INFO_EVENT = 'networkInfo';

const NETWORK_TYPES: ReadonlySet<string> = new Set([
  'wifi',
  'cellular',
  'ethernet',
  'other',
  'none',
  'unknown',
]);
const CELLULAR_GENERATIONS: ReadonlySet<string> = new Set([
  '2g',
  '3g',
  '4g',
  '5g',
]);

const listeners = new Set<NetworkInfoListener>();
let listeningForEvents = false;

function requireNetworkInfoModule() {
  'background only';
  return requireNativeModule();
}

function installEventListener(): void {
  'background only';
  if (listeningForEvents) return;
  listeningForEvents = true;
  lynx
    .getJSModule('GlobalEventEmitter')
    .addListener(NETWORK_INFO_EVENT, dispatchEvent);
}

function decodeSnapshot(value: unknown): NetworkInfoSnapshot | null {
  'background only';
  if (typeof value !== 'object' || value === null) return null;
  const payload = value as NetworkInfoEventPayload;
  if (
    typeof payload.connected !== 'boolean' ||
    typeof payload.type !== 'string' ||
    !NETWORK_TYPES.has(payload.type)
  ) {
    return null;
  }
  const generation =
    typeof payload.cellularGeneration === 'string' &&
    CELLULAR_GENERATIONS.has(payload.cellularGeneration)
      ? (payload.cellularGeneration as CellularGeneration)
      : null;
  return {
    connected: payload.connected,
    type: payload.type as NetworkType,
    cellularGeneration: generation,
    timestamp:
      typeof payload.timestamp === 'number' &&
      Number.isFinite(payload.timestamp)
        ? payload.timestamp
        : Date.now(),
  };
}

function dispatchEvent(value: unknown): void {
  'background only';
  if (typeof value !== 'object' || value === null || listeners.size === 0) {
    return;
  }
  const payload = value as NetworkInfoEventPayload;
  if (typeof payload.error === 'string' && payload.error.length > 0) {
    for (const listener of [...listeners]) {
      listener.onError?.(payload.error);
    }
    return;
  }
  const snapshot = decodeSnapshot(payload);
  if (snapshot === null) return;
  for (const listener of [...listeners]) {
    listener.onChange(snapshot);
  }
}

/** Resolves after a command-style method (error-string ack) succeeds. */
function command(
  action: (
    module: NonNullable<ReturnType<typeof requireNetworkInfoModule>>,
    callback: (error: string) => void,
  ) => void,
): Promise<void> {
  'background only';
  return completeNativeCall((callback) =>
    action(requireNetworkInfoModule(), callback),
  );
}

/** Network reachability snapshots and change observation. */
export const networkInfo = {
  /** Reads the current network state once. */
  getInfo(): Promise<NetworkInfoSnapshot> {
    'background only';
    return new Promise((resolve, reject) => {
      try {
        requireNetworkInfoModule().getInfo((resultValue) => {
          'background only';
          try {
            const result = decodeNativeEnvelope(
              resultValue,
              'NetworkInfo',
            ) as NetworkInfoValueResult;
            if (typeof result.error === 'string' && result.error.length > 0) {
              reject(new Error(result.error));
              return;
            }
            const snapshot = decodeSnapshot(result.value);
            if (snapshot === null) {
              throw new Error('NetworkInfo returned an invalid snapshot');
            }
            resolve(snapshot);
          } catch (error) {
            reject(error instanceof Error ? error : new Error(String(error)));
          }
        });
      } catch (error) {
        reject(error instanceof Error ? error : new Error(String(error)));
      }
    });
  },

  /**
   * Subscribes to network changes. The first observer registers the native
   * listener and the last unsubscribe tears it down; an immediate snapshot is
   * emitted right after each (re)registration so observers always start with
   * the current state. Returns an unsubscribe function that is safe to call
   * more than once.
   */
  observe(
    onChange: (snapshot: NetworkInfoSnapshot) => void,
    onError?: (message: string) => void,
  ): () => void {
    'background only';
    installEventListener();
    const entry: NetworkInfoListener = { onChange, onError };
    const startsStream = listeners.size === 0;
    listeners.add(entry);
    if (startsStream) {
      void command((module, callback) => module.start(callback)).catch(
        (error: Error) => {
          'background only';
          for (const listener of [...listeners]) {
            listener.onError?.(error.message);
          }
        },
      );
    }
    let removed = false;
    return () => {
      'background only';
      if (removed) return;
      removed = true;
      listeners.delete(entry);
      if (listeners.size === 0) {
        void command((module, callback) => module.stop(callback)).catch(
          () => {},
        );
      }
    };
  },
};
