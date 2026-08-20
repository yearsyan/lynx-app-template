/**
 * Local-file audio playback over the native AudioPlayer module. Commands
 * resolve through the shared Promise layer; state changes, throttled
 * progress, end-of-stream and playback errors arrive through the Lynx
 * GlobalEventEmitter on the `audioPlayer` event.
 */
import {
  decodeNativeEnvelope,
  requireNativeModule,
} from '@lynx-app/native-runtime';
import { AUDIO_PLAYER_MODULE_NAME } from './native.generated.js';

export * from './native.generated.js';

export type AudioPlayerUsage = 'media' | 'ambient' | 'alarm' | 'notification';
export type AudioPlayerState = 'loading' | 'paused' | 'playing' | 'stopped';
export type AudioPlayerInterruption = 'pause' | 'duck' | 'resume' | 'unduck';
export type AudioPlayerEventType = 'state' | 'progress' | 'end' | 'error';

export interface AudioPlayerOptions {
  /** Local `file://` (or Android `content://`) source, e.g. from FileSystem. */
  uri: string;
  /** Audio stream to route through; defaults to `media`. */
  usage?: AudioPlayerUsage;
  /** Start as soon as the file is prepared; defaults to `false`. */
  autoPlay?: boolean;
  /** Minimum gap between progress events; 50..10000, defaults to 250. */
  progressIntervalMs?: number;
}

export interface AudioPlayerStateEvent {
  type: 'state';
  state: AudioPlayerState;
  positionMs: number;
  durationMs: number;
  interruption?: AudioPlayerInterruption;
}

export interface AudioPlayerProgressEvent {
  type: 'progress';
  state: 'playing';
  positionMs: number;
  durationMs: number;
}

export interface AudioPlayerEndEvent {
  type: 'end';
}

export interface AudioPlayerErrorEvent {
  type: 'error';
  error: string;
}

export interface AudioPlayerEventMap {
  state: AudioPlayerStateEvent;
  progress: AudioPlayerProgressEvent;
  end: AudioPlayerEndEvent;
  error: AudioPlayerErrorEvent;
}

export interface AudioPlayerProps {
  state: AudioPlayerState;
  positionMs: number;
  durationMs: number;
  usage: AudioPlayerUsage;
  rate: number;
  volume: number;
}

interface AudioPlayerEventPayload {
  id?: unknown;
  type?: unknown;
  state?: unknown;
  positionMs?: unknown;
  durationMs?: unknown;
  interruption?: unknown;
  error?: unknown;
}

interface AudioPlayerPropsPayload {
  error?: unknown;
  state?: unknown;
  positionMs?: unknown;
  durationMs?: unknown;
  usage?: unknown;
  rate?: unknown;
  volume?: unknown;
}

type AudioPlayerListener<T extends AudioPlayerEventType> = (
  event: AudioPlayerEventMap[T],
) => void;

type UntypedAudioPlayerListener = (
  event: AudioPlayerEventMap[AudioPlayerEventType],
) => void;

export const AUDIO_PLAYER_EVENT = 'audioPlayer';

const USAGES: readonly AudioPlayerUsage[] = [
  'media',
  'ambient',
  'alarm',
  'notification',
];

const players = new Map<string, AudioPlayerHandle>();
let nextPlayerID = 0;
let listeningForEvents = false;

function requireAudioPlayerModule() {
  'background only';
  return requireNativeModule(AUDIO_PLAYER_MODULE_NAME);
}

function installEventListener(): void {
  'background only';
  if (listeningForEvents) return;
  listeningForEvents = true;
  lynx
    .getJSModule('GlobalEventEmitter')
    .addListener(AUDIO_PLAYER_EVENT, dispatchEvent);
}

function dispatchEvent(value: unknown): void {
  'background only';
  if (typeof value !== 'object' || value === null) return;
  const payload = value as AudioPlayerEventPayload;
  if (typeof payload.id !== 'string') return;
  players.get(payload.id)?.receiveEvent(payload);
}

function invoke(
  action: (callback: (error: string) => void) => void,
): Promise<void> {
  'background only';
  return new Promise((resolve, reject) => {
    try {
      action((error) => {
        'background only';
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

function isFiniteNumber(value: unknown): value is number {
  return typeof value === 'number' && Number.isFinite(value);
}

function isUsage(value: unknown): value is AudioPlayerUsage {
  return (
    typeof value === 'string' && USAGES.includes(value as AudioPlayerUsage)
  );
}

function isState(value: unknown): value is AudioPlayerState {
  return (
    value === 'loading' ||
    value === 'paused' ||
    value === 'playing' ||
    value === 'stopped'
  );
}

function isInterruption(value: unknown): value is AudioPlayerInterruption {
  return (
    value === 'pause' ||
    value === 'duck' ||
    value === 'resume' ||
    value === 'unduck'
  );
}

/** One audio player. `created` settles once the file is prepared natively. */
export class AudioPlayerHandle {
  readonly id: string;
  readonly created: Promise<void>;

  private readonly listeners: Map<
    AudioPlayerEventType,
    Set<UntypedAudioPlayerListener>
  > = new Map();
  private resolveCreated: () => void = () => {};
  private rejectCreated: (error: Error) => void = () => {};
  private createdSettled = false;
  private destroyed = false;

  constructor(options: AudioPlayerOptions) {
    const uri = options.uri;
    if (typeof uri !== 'string' || uri.trim().length === 0) {
      throw new Error('AudioPlayer requires a local file URI');
    }
    const scheme = uri.split(':', 1)[0]?.toLowerCase() ?? '';
    if (scheme === 'http' || scheme === 'https') {
      throw new Error(
        'AudioPlayer only supports local files, not http(s) URLs',
      );
    }
    if (scheme !== 'file' && scheme !== 'content') {
      throw new Error('AudioPlayer requires a file:// (or content://) URI');
    }
    const usage = options.usage ?? 'media';
    if (!isUsage(usage)) {
      throw new Error(`Invalid AudioPlayer usage: ${String(usage)}`);
    }
    const progressIntervalMs = options.progressIntervalMs ?? 250;
    if (
      !Number.isInteger(progressIntervalMs) ||
      progressIntervalMs < 50 ||
      progressIntervalMs > 10_000
    ) {
      throw new Error(
        'progressIntervalMs must be an integer between 50 and 10000',
      );
    }

    nextPlayerID += 1;
    this.id = `ap-${Date.now().toString(36)}-${nextPlayerID.toString(36)}`;
    this.created = new Promise((resolve, reject) => {
      this.resolveCreated = resolve;
      this.rejectCreated = reject;
    });

    installEventListener();
    players.set(this.id, this);
    void invoke((callback) =>
      requireAudioPlayerModule().create(
        {
          id: this.id,
          uri,
          usage,
          autoPlay: options.autoPlay === true,
          progressIntervalMs,
        },
        callback,
      ),
    ).then(
      () => {
        'background only';
        if (!this.destroyed) {
          this.createdSettled = true;
          this.resolveCreated();
        }
      },
      (error: Error) => {
        'background only';
        this.dispose();
        if (!this.createdSettled) {
          this.createdSettled = true;
          this.rejectCreated(error);
        }
      },
    );
  }

  addEventListener<T extends AudioPlayerEventType>(
    type: T,
    listener: AudioPlayerListener<T>,
  ): () => void {
    'background only';
    const listeners = this.listeners.get(type) ?? new Set();
    listeners.add(listener as UntypedAudioPlayerListener);
    this.listeners.set(type, listeners);
    return () => {
      'background only';
      this.removeEventListener(type, listener);
    };
  }

  removeEventListener<T extends AudioPlayerEventType>(
    type: T,
    listener: AudioPlayerListener<T>,
  ): void {
    'background only';
    this.listeners.get(type)?.delete(listener as UntypedAudioPlayerListener);
  }

  play(): Promise<void> {
    'background only';
    return this.command((module, callback) => module.play(this.id, callback));
  }

  pause(): Promise<void> {
    'background only';
    return this.command((module, callback) => module.pause(this.id, callback));
  }

  seek(positionMs: number): Promise<void> {
    'background only';
    if (!isFiniteNumber(positionMs) || positionMs < 0) {
      return Promise.reject(
        new Error('seek positionMs must be a non-negative number'),
      );
    }
    return this.command((module, callback) =>
      module.seek(this.id, Math.round(positionMs), callback),
    );
  }

  stop(): Promise<void> {
    'background only';
    return this.command((module, callback) => module.stop(this.id, callback));
  }

  setRate(rate: number): Promise<void> {
    'background only';
    if (!isFiniteNumber(rate) || rate < 0.25 || rate > 4) {
      return Promise.reject(new Error('rate must be between 0.25 and 4'));
    }
    return this.command((module, callback) =>
      module.setRate(this.id, rate, callback),
    );
  }

  setVolume(volume: number): Promise<void> {
    'background only';
    if (!isFiniteNumber(volume) || volume < 0 || volume > 1) {
      return Promise.reject(new Error('volume must be between 0 and 1'));
    }
    return this.command((module, callback) =>
      module.setVolume(this.id, volume, callback),
    );
  }

  getProps(): Promise<AudioPlayerProps> {
    'background only';
    if (this.destroyed) {
      return Promise.reject(new Error('AudioPlayer has been destroyed'));
    }
    return new Promise((resolve, reject) => {
      requireAudioPlayerModule().getProps(this.id, (result) => {
        'background only';
        try {
          const props = decodeNativeEnvelope(
            result,
            'AudioPlayer',
          ) as AudioPlayerPropsPayload;
          if (typeof props.error === 'string' && props.error.length > 0) {
            reject(new Error(props.error));
            return;
          }
          if (!isState(props.state) || !isUsage(props.usage)) {
            throw new Error('AudioPlayer returned invalid playback properties');
          }
          resolve({
            state: props.state,
            positionMs: isFiniteNumber(props.positionMs) ? props.positionMs : 0,
            durationMs: isFiniteNumber(props.durationMs) ? props.durationMs : 0,
            usage: props.usage,
            rate: isFiniteNumber(props.rate) ? props.rate : 1,
            volume: isFiniteNumber(props.volume) ? props.volume : 1,
          });
        } catch (error) {
          reject(error instanceof Error ? error : new Error(String(error)));
        }
      });
    });
  }

  /** Releases the native player and all listeners; safe to call twice. */
  destroy(): void {
    'background only';
    if (this.destroyed) return;
    if (!this.createdSettled) {
      this.createdSettled = true;
      this.rejectCreated(
        new Error('AudioPlayer was destroyed before creation completed'),
      );
    }
    this.dispose();
    void invoke((callback) =>
      requireAudioPlayerModule().release(this.id, callback),
    ).catch(() => {});
  }

  /** @internal Called only by the shared native event dispatcher. */
  receiveEvent(payload: AudioPlayerEventPayload): void {
    'background only';
    if (this.destroyed) return;
    switch (payload.type) {
      case 'state': {
        if (!isState(payload.state)) return;
        const interruption = isInterruption(payload.interruption)
          ? payload.interruption
          : undefined;
        this.emit({
          type: 'state',
          state: payload.state,
          positionMs: isFiniteNumber(payload.positionMs)
            ? payload.positionMs
            : 0,
          durationMs: isFiniteNumber(payload.durationMs)
            ? payload.durationMs
            : 0,
          ...(interruption === undefined ? {} : { interruption }),
        });
        break;
      }
      case 'progress': {
        this.emit({
          type: 'progress',
          state: 'playing',
          positionMs: isFiniteNumber(payload.positionMs)
            ? payload.positionMs
            : 0,
          durationMs: isFiniteNumber(payload.durationMs)
            ? payload.durationMs
            : 0,
        });
        break;
      }
      case 'end': {
        this.emit({ type: 'end' });
        break;
      }
      case 'error': {
        this.emit({
          type: 'error',
          error:
            typeof payload.error === 'string' && payload.error.length > 0
              ? payload.error
              : 'Unknown AudioPlayer error',
        });
        break;
      }
      default:
        break;
    }
  }

  private command(
    action: (
      module: NonNullable<ReturnType<typeof requireAudioPlayerModule>>,
      callback: (error: string) => void,
    ) => void,
  ): Promise<void> {
    'background only';
    if (this.destroyed) {
      return Promise.reject(new Error('AudioPlayer has been destroyed'));
    }
    return invoke((callback) => action(requireAudioPlayerModule(), callback));
  }

  private dispose(): void {
    'background only';
    this.destroyed = true;
    players.delete(this.id);
    this.listeners.clear();
  }

  private emit<T extends AudioPlayerEventType>(
    event: AudioPlayerEventMap[T],
  ): void {
    'background only';
    const listeners = this.listeners.get(event.type);
    if (listeners === undefined) return;
    for (const listener of [...listeners]) {
      try {
        listener(event);
      } catch (error) {
        console.error(
          `AudioPlayer ${event.type} listener failed: ${String(error)}`,
        );
      }
    }
  }
}

export const audioPlayer = {
  /**
   * Creates a player for a local audio file. The returned handle is usable
   * immediately; its `created` promise settles once the file is prepared
   * (or rejects with `file-not-found` / `unsupported-format` / `read-failed`).
   */
  create(options: AudioPlayerOptions): AudioPlayerHandle {
    'background only';
    return new AudioPlayerHandle(options);
  },
};
