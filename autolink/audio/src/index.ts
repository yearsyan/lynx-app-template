/**
 * Local-file audio playback and microphone recording over the native Audio
 * module. Commands resolve through the shared Promise layer; state changes,
 * throttled progress, end-of-stream and errors arrive through the Lynx
 * GlobalEventEmitter on the `audioPlayer` / `audioRecorder` events.
 */
import {
  decodeNativeEnvelope,
  requireNativeModule,
} from './bridge.generated.js';

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

interface AudioRecorderEventPayload {
  id?: unknown;
  type?: unknown;
  state?: unknown;
  durationMs?: unknown;
  uri?: unknown;
  error?: unknown;
}

interface AudioRecorderResultPayload {
  error?: unknown;
  state?: unknown;
  uri?: unknown;
  durationMs?: unknown;
  sizeBytes?: unknown;
}

type AudioPlayerListener<T extends AudioPlayerEventType> = (
  event: AudioPlayerEventMap[T],
) => void;

type UntypedAudioPlayerListener = (
  event: AudioPlayerEventMap[AudioPlayerEventType],
) => void;

export type AudioRecorderState =
  | 'idle'
  | 'recording'
  | 'paused'
  | 'stopped'
  | 'failed';
export type AudioRecorderEventType = 'state' | 'progress' | 'end' | 'error';

export interface AudioRecorderOptions {
  /** Auto-stop and deliver after this long; 100..600000, defaults to off. */
  durationLimitMs?: number;
  /** Minimum gap between progress events; 50..10000, defaults to 250. */
  progressIntervalMs?: number;
}

export interface AudioRecorderStateEvent {
  type: 'state';
  state: AudioRecorderState;
  durationMs: number;
}

export interface AudioRecorderProgressEvent {
  type: 'progress';
  state: 'recording';
  durationMs: number;
}

export interface AudioRecorderEndEvent {
  type: 'end';
  uri: string;
  durationMs: number;
}

export interface AudioRecorderErrorEvent {
  type: 'error';
  error: string;
}

export interface AudioRecorderEventMap {
  state: AudioRecorderStateEvent;
  progress: AudioRecorderProgressEvent;
  end: AudioRecorderEndEvent;
  error: AudioRecorderErrorEvent;
}

export interface AudioRecorderProps {
  state: AudioRecorderState;
  durationMs: number;
  uri: string | null;
}

export interface AudioRecorderResult {
  uri: string;
  durationMs: number;
  sizeBytes: number | null;
}

export const AUDIO_PLAYER_EVENT = 'audioPlayer';
export const AUDIO_RECORDER_EVENT = 'audioRecorder';

const USAGES: readonly AudioPlayerUsage[] = [
  'media',
  'ambient',
  'alarm',
  'notification',
];

const players = new Map<string, AudioPlayerHandle>();
const recorders = new Map<string, AudioRecorderHandle>();
let nextPlayerID = 0;
let nextRecorderID = 0;
let listeningForEvents = false;

function requireAudioModule() {
  'background only';
  return requireNativeModule();
}

function installEventListener(): void {
  'background only';
  if (listeningForEvents) return;
  listeningForEvents = true;
  const emitter = lynx.getJSModule('GlobalEventEmitter');
  emitter.addListener(AUDIO_PLAYER_EVENT, dispatchEvent);
  emitter.addListener(AUDIO_RECORDER_EVENT, dispatchRecorderEvent);
}

function dispatchEvent(value: unknown): void {
  'background only';
  if (typeof value !== 'object' || value === null) return;
  const payload = value as AudioPlayerEventPayload;
  if (typeof payload.id !== 'string') return;
  players.get(payload.id)?.receiveEvent(payload);
}

function dispatchRecorderEvent(value: unknown): void {
  'background only';
  if (typeof value !== 'object' || value === null) return;
  const payload = value as AudioRecorderEventPayload;
  if (typeof payload.id !== 'string') return;
  recorders.get(payload.id)?.receiveEvent(payload);
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

function isRecorderState(value: unknown): value is AudioRecorderState {
  return (
    value === 'idle' ||
    value === 'recording' ||
    value === 'paused' ||
    value === 'stopped' ||
    value === 'failed'
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
      requireAudioModule().create(
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
      requireAudioModule().getProps(this.id, (result) => {
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
      requireAudioModule().release(this.id, callback),
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
      module: NonNullable<ReturnType<typeof requireAudioModule>>,
      callback: (error: string) => void,
    ) => void,
  ): Promise<void> {
    'background only';
    if (this.destroyed) {
      return Promise.reject(new Error('AudioPlayer has been destroyed'));
    }
    return invoke((callback) => action(requireAudioModule(), callback));
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

/** One microphone recorder; the file URI is delivered by `stop()` / `end`. */
export class AudioRecorderHandle {
  readonly id: string;

  private readonly listeners: Map<
    AudioRecorderEventType,
    Set<UntypedAudioRecorderListener>
  > = new Map();
  private lastResult: AudioRecorderResult | null = null;
  private destroyed = false;

  constructor(options: AudioRecorderOptions) {
    const durationLimitMs = options.durationLimitMs ?? 0;
    if (
      !Number.isInteger(durationLimitMs) ||
      durationLimitMs < 0 ||
      durationLimitMs > 600_000 ||
      (durationLimitMs !== 0 && durationLimitMs < 100)
    ) {
      throw new Error(
        'durationLimitMs must be between 100 and 600000, or omitted to disable',
      );
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

    nextRecorderID += 1;
    this.id = `ar-${Date.now().toString(36)}-${nextRecorderID.toString(36)}`;

    installEventListener();
    recorders.set(this.id, this);
    void invoke((callback) =>
      requireAudioModule().recorderCreate(
        {
          id: this.id,
          durationLimitMs,
          progressIntervalMs,
        },
        callback,
      ),
    ).catch((error: Error) => {
      'background only';
      recorders.delete(this.id);
      this.emit({ type: 'error', error: error.message });
    });
  }

  addEventListener<T extends AudioRecorderEventType>(
    type: T,
    listener: AudioRecorderListener<T>,
  ): () => void {
    'background only';
    const listeners = this.listeners.get(type) ?? new Set();
    listeners.add(listener as UntypedAudioRecorderListener);
    this.listeners.set(type, listeners);
    return () => {
      'background only';
      this.removeEventListener(type, listener);
    };
  }

  removeEventListener<T extends AudioRecorderEventType>(
    type: T,
    listener: AudioRecorderListener<T>,
  ): void {
    'background only';
    this.listeners.get(type)?.delete(listener as UntypedAudioRecorderListener);
  }

  /** Requests the microphone and starts writing the AAC file. */
  start(): Promise<void> {
    'background only';
    return this.command((module, callback) =>
      module.recorderStart(this.id, callback),
    );
  }

  pause(): Promise<void> {
    'background only';
    return this.command((module, callback) =>
      module.recorderPause(this.id, callback),
    );
  }

  resume(): Promise<void> {
    'background only';
    return this.command((module, callback) =>
      module.recorderResume(this.id, callback),
    );
  }

  /** Stops recording and resolves with the recorded file. */
  stop(): Promise<AudioRecorderResult> {
    'background only';
    if (this.destroyed) {
      return Promise.reject(new Error('AudioRecorder has been destroyed'));
    }
    return new Promise((resolve, reject) => {
      requireAudioModule().recorderStop(this.id, (result) => {
        'background only';
        this.settleResult(result, reject, resolve);
      });
    });
  }

  /** Discards the recording and returns the session to the idle state. */
  cancel(): Promise<void> {
    'background only';
    return this.command((module, callback) =>
      module.recorderCancel(this.id, callback),
    );
  }

  getProps(): Promise<AudioRecorderProps> {
    'background only';
    if (this.destroyed) {
      return Promise.reject(new Error('AudioRecorder has been destroyed'));
    }
    return new Promise((resolve, reject) => {
      requireAudioModule().recorderGetProps(this.id, (result) => {
        'background only';
        try {
          const props = decodeNativeEnvelope(
            result,
            'AudioRecorder',
          ) as AudioRecorderResultPayload;
          if (typeof props.error === 'string' && props.error.length > 0) {
            reject(new Error(props.error));
            return;
          }
          if (!isRecorderState(props.state)) {
            throw new Error('AudioRecorder returned invalid properties');
          }
          resolve({
            state: props.state,
            durationMs: isFiniteNumber(props.durationMs) ? props.durationMs : 0,
            uri:
              typeof props.uri === 'string' && props.uri.length > 0
                ? props.uri
                : null,
          });
        } catch (error) {
          reject(error instanceof Error ? error : new Error(String(error)));
        }
      });
    });
  }

  /** Stops any active recording, releases the native session and listeners. */
  destroy(): void {
    'background only';
    if (this.destroyed) return;
    this.destroyed = true;
    recorders.delete(this.id);
    this.listeners.clear();
    void invoke((callback) =>
      requireAudioModule().recorderRelease(this.id, callback),
    ).catch(() => {});
  }

  /** @internal Called only by the shared native event dispatcher. */
  receiveEvent(payload: AudioRecorderEventPayload): void {
    'background only';
    if (this.destroyed) return;
    switch (payload.type) {
      case 'state': {
        if (!isRecorderState(payload.state)) return;
        this.emit({
          type: 'state',
          state: payload.state,
          durationMs: isFiniteNumber(payload.durationMs)
            ? payload.durationMs
            : 0,
        });
        break;
      }
      case 'progress': {
        this.emit({
          type: 'progress',
          state: 'recording',
          durationMs: isFiniteNumber(payload.durationMs)
            ? payload.durationMs
            : 0,
        });
        break;
      }
      case 'end': {
        if (typeof payload.uri !== 'string' || payload.uri.length === 0) return;
        this.lastResult = {
          uri: payload.uri,
          durationMs: isFiniteNumber(payload.durationMs)
            ? payload.durationMs
            : 0,
          sizeBytes: null,
        };
        this.emit({ ...this.lastResult, type: 'end' });
        break;
      }
      case 'error': {
        this.emit({
          type: 'error',
          error:
            typeof payload.error === 'string' && payload.error.length > 0
              ? payload.error
              : 'Unknown AudioRecorder error',
        });
        break;
      }
      default:
        break;
    }
  }

  private settleResult(
    result: unknown,
    reject: (error: Error) => void,
    resolve: (value: AudioRecorderResult) => void,
  ): void {
    'background only';
    try {
      const envelope = decodeNativeEnvelope(
        result,
        'AudioRecorder',
      ) as AudioRecorderResultPayload;
      if (typeof envelope.error === 'string' && envelope.error.length > 0) {
        reject(new Error(envelope.error));
        return;
      }
      const uri = envelope.uri;
      if (typeof uri !== 'string' || uri.length === 0) {
        // A duration-limit end already delivered the file; replay it.
        if (this.lastResult !== null) {
          resolve(this.lastResult);
          return;
        }
        throw new Error('AudioRecorder returned no file URI');
      }
      this.lastResult = {
        uri,
        durationMs: isFiniteNumber(envelope.durationMs)
          ? envelope.durationMs
          : 0,
        sizeBytes: isFiniteNumber(envelope.sizeBytes)
          ? envelope.sizeBytes
          : null,
      };
      resolve(this.lastResult);
    } catch (error) {
      reject(error instanceof Error ? error : new Error(String(error)));
    }
  }

  private command(
    action: (
      module: NonNullable<ReturnType<typeof requireAudioModule>>,
      callback: (error: string) => void,
    ) => void,
  ): Promise<void> {
    'background only';
    if (this.destroyed) {
      return Promise.reject(new Error('AudioRecorder has been destroyed'));
    }
    return invoke((callback) => action(requireAudioModule(), callback));
  }

  private emit<T extends AudioRecorderEventType>(
    event: AudioRecorderEventMap[T],
  ): void {
    'background only';
    const listeners = this.listeners.get(event.type);
    if (listeners === undefined) return;
    for (const listener of [...listeners]) {
      try {
        listener(event);
      } catch (error) {
        console.error(
          `AudioRecorder ${event.type} listener failed: ${String(error)}`,
        );
      }
    }
  }
}

type AudioRecorderListener<T extends AudioRecorderEventType> = (
  event: AudioRecorderEventMap[T],
) => void;

type UntypedAudioRecorderListener = (
  event: AudioRecorderEventMap[AudioRecorderEventType],
) => void;

export const audioRecorder = {
  /**
   * Creates a recording session. Grant the microphone permission first
   * (`permissions.request({ type: 'microphone' })`), then `start()`; the
   * recorded AAC file lands in the host cache directory and is delivered
   * by `stop()` or the `end` event (`durationLimitMs` reached).
   */
  create(options: AudioRecorderOptions): AudioRecorderHandle {
    'background only';
    return new AudioRecorderHandle(options);
  },
};
