import { media } from '@kit.MediaKit';
import { audio } from '@kit.AudioKit';
import { abilityAccessCtrl, bundleManager, common } from '@kit.AbilityKit';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { LynxContext, LynxModule, LynxViewClient } from '@lynx/lynx';

export interface NativeAudioPlayerOptions {
  id: string;
  uri: string;
  usage: string;
  autoPlay: boolean;
  progressIntervalMs: number;
}

class NativeAudioPlayerEventPayload {
  id: string;
  type: string;
  state: string = '';
  positionMs: number = 0;
  durationMs: number = 0;
  interruption: string = '';
  error: string = '';

  constructor(id: string, type: string) {
    this.id = id;
    this.type = type;
  }
}

const STATE_LOADING: string = 'loading';
const STATE_PAUSED: string = 'paused';
const STATE_PLAYING: string = 'playing';
const STATE_STOPPED: string = 'stopped';

function streamUsageOf(usage: string): audio.StreamUsage {
  if (usage === 'alarm') {
    return audio.StreamUsage.STREAM_USAGE_ALARM;
  }
  if (usage === 'notification') {
    return audio.StreamUsage.STREAM_USAGE_NOTIFICATION_RINGTONE;
  }
  return audio.StreamUsage.STREAM_USAGE_MUSIC;
}

function nearestSpeed(rate: number): media.PlaybackSpeed {
  // HarmonyOS supports a discrete speed set; snap to the nearest.
  const allowed: Array<[number, media.PlaybackSpeed]> = [
    [0.5, media.PlaybackSpeed.SPEED_FORWARD_0_50_X],
    [0.75, media.PlaybackSpeed.SPEED_FORWARD_0_75_X],
    [1.0, media.PlaybackSpeed.SPEED_FORWARD_1_00_X],
    [1.25, media.PlaybackSpeed.SPEED_FORWARD_1_25_X],
    [1.5, media.PlaybackSpeed.SPEED_FORWARD_1_50_X],
    [1.75, media.PlaybackSpeed.SPEED_FORWARD_1_75_X],
    [2.0, media.PlaybackSpeed.SPEED_FORWARD_2_00_X],
    [3.0, media.PlaybackSpeed.SPEED_FORWARD_3_00_X],
  ];
  let best: media.PlaybackSpeed = media.PlaybackSpeed.SPEED_FORWARD_1_00_X;
  let bestDistance: number = Number.MAX_VALUE;
  for (const entry of allowed) {
    const distance: number = Math.abs(entry[0] - rate);
    if (distance < bestDistance) {
      bestDistance = distance;
      best = entry[1];
    }
  }
  return best;
}

/** Owns one AVPlayer plus its open fd; HarmonyOS keeps fd alive during playback. */
class NativeAudioPlayerHandle {
  readonly id: string;
  readonly usage: string;
  readonly progressIntervalMs: number;
  readonly context: LynxContext;

  state: string = STATE_LOADING;
  desiredRate: number = 1.0;
  userVolume: number = 1.0;
  released: boolean = false;
  startOnPrepared: boolean = false;
  pendingCreate: ((error: string) => void) | undefined = undefined;
  onTerminal: (() => void) | undefined = undefined;
  lastProgressAt: number = 0;

  private avPlayer: media.AVPlayer | undefined = undefined;
  private file: fs.File | undefined = undefined;

  constructor(id: string, usage: string, progressIntervalMs: number, autoPlay: boolean, context: LynxContext) {
    this.id = id;
    this.usage = usage;
    this.progressIntervalMs = progressIntervalMs;
    this.startOnPrepared = autoPlay;
    this.context = context;
  }

  async create(options: NativeAudioPlayerOptions): Promise<string> {
    try {
      this.file = fs.openSync(options.uri, fs.OpenMode.READ_ONLY);
    } catch (error) {
      this.closeFile();
      return `file-not-found: Unable to open ${options.uri}`;
    }
    try {
      this.avPlayer = await media.createAVPlayer();
    } catch (error) {
      this.closeFile();
      return this.messageOf(error, 'read-failed: Unable to create the audio player');
    }
    const player = this.avPlayer;
    this.installListeners(player);
    try {
      player.url = `fd://${this.file.fd.toString()}`;
    } catch (error) {
      return this.messageOf(error, 'read-failed: Unable to open the audio source');
    }
    return '';
  }

  private installListeners(player: media.AVPlayer): void {
    player.on('stateChange', (next: string, _reason: media.StateChangeReason) => {
      this.onNativeStateChange(next);
    });
    player.on('error', (error: BusinessError) => {
      this.onNativeError(error.code);
    });
    player.on('timeUpdate', (time: number) => {
      this.onNativeTimeUpdate(time);
    });
    player.on('endOfStream', () => {
      this.onNativeEndOfStream();
    });
    if (this.usage !== 'ambient') {
      // The system already applies focus policy; this only reports it.
      player.on('audioInterrupt', (event: audio.InterruptEvent) => {
        this.onNativeInterrupt(event);
      });
    }
  }

  play(callback: (error: string) => void): void {
    const player = this.avPlayer;
    if (this.released || player === undefined) {
      callback('AudioPlayer has been released');
      return;
    }
    if (this.state === STATE_PLAYING) {
      callback('');
      return;
    }
    if (this.state === STATE_LOADING) {
      callback('AudioPlayer is still loading');
      return;
    }
    if (this.state === STATE_STOPPED) {
      this.startOnPrepared = true;
      this.state = STATE_LOADING;
      this.emitState(STATE_LOADING);
      player.prepare().catch((_error: Error) => {
      });
      callback('');
      return;
    }
    player.play().catch((_error: Error) => {
    });
    callback('');
  }

  pause(callback: (error: string) => void): void {
    const player = this.avPlayer;
    if (this.released || player === undefined) {
      callback('AudioPlayer has been released');
      return;
    }
    if (this.state === STATE_PAUSED || this.state === STATE_STOPPED) {
      callback('');
      return;
    }
    if (this.state === STATE_LOADING) {
      this.startOnPrepared = false;
      callback('');
      return;
    }
    player.pause().catch((_error: Error) => {
    });
    callback('');
  }

  seek(positionMs: number, callback: (error: string) => void): void {
    const player = this.avPlayer;
    if (this.released || player === undefined) {
      callback('AudioPlayer has been released');
      return;
    }
    if (this.state === STATE_LOADING || this.state === STATE_STOPPED) {
      callback(`AudioPlayer is not seekable in the ${this.state} state`);
      return;
    }
    const clamped: number = Math.max(0, Math.min(positionMs, Math.max(this.durationMs(), 0)));
    // seek() is void on HarmonyOS; completion arrives via seekDone.
    player.seek(clamped, media.SeekMode.SEEK_CLOSEST);
    this.emitState(this.state);
    callback('');
  }

  stop(callback: (error: string) => void): void {
    const player = this.avPlayer;
    if (this.released || player === undefined) {
      callback('AudioPlayer has been released');
      return;
    }
    if (this.state === STATE_STOPPED) {
      callback('');
      return;
    }
    if (this.state !== STATE_LOADING) {
      player.stop().catch((_error: Error) => {
      });
    }
    this.state = STATE_STOPPED;
    this.emitState(STATE_STOPPED);
    callback('');
  }

  setRate(rate: number, callback: (error: string) => void): void {
    const player = this.avPlayer;
    if (this.released || player === undefined) {
      callback('AudioPlayer has been released');
      return;
    }
    this.desiredRate = rate;
    if (this.state === STATE_PLAYING) {
      // setSpeed() is void on HarmonyOS; completion arrives via speedDone.
      player.setSpeed(nearestSpeed(rate));
    }
    callback('');
  }

  setVolume(volume: number, callback: (error: string) => void): void {
    const player = this.avPlayer;
    if (this.released || player === undefined) {
      callback('AudioPlayer has been released');
      return;
    }
    this.userVolume = volume;
    // setVolume() is void on HarmonyOS; completion arrives via volumeChange.
    player.setVolume(volume);
    callback('');
  }

  getProps(callback: (resultJSON: string) => void): void {
    const player = this.avPlayer;
    if (this.released || player === undefined) {
      callback(JSON.stringify({ error: 'AudioPlayer is not available' }));
      return;
    }
    callback(JSON.stringify({
      state: this.state,
      positionMs: this.state === STATE_STOPPED ? 0 : Math.round(player.currentTime),
      durationMs: this.durationMs(),
      usage: this.usage,
      rate: this.desiredRate,
      volume: this.userVolume,
    }));
  }

  release(): void {
    if (this.released) {
      return;
    }
    this.released = true;
    const callback = this.pendingCreate;
    this.pendingCreate = undefined;
    if (callback !== undefined) {
      callback('AudioPlayer has been released');
    }
    const player = this.avPlayer;
    this.avPlayer = undefined;
    if (player !== undefined) {
      player.release().catch((_error: Error) => {
      });
    }
    this.closeFile();
  }

  private onNativeStateChange(next: string): void {
    const player = this.avPlayer;
    if (this.released || player === undefined) {
      return;
    }
    if (next === 'initialized') {
      // audioRendererInfo is only settable in the initialized state.
      player.audioRendererInfo = {
        usage: streamUsageOf(this.usage),
        rendererFlags: 0,
      } as audio.AudioRendererInfo;
      player.prepare().catch((_error: Error) => {
        // Prepare failures surface through the AVPlayer error listener.
      });
      return;
    }
    if (next === 'prepared') {
      const autoStart: boolean = this.startOnPrepared;
      this.startOnPrepared = false;
      this.state = STATE_PAUSED;
      this.emitState(STATE_PAUSED);
      if (autoStart) {
        player.play().catch((_error: Error) => {
        });
      }
      this.finishPrepare('');
      return;
    }
    if (next === 'playing') {
      this.state = STATE_PLAYING;
      this.emitState(STATE_PLAYING);
      return;
    }
    if (next === 'paused') {
      this.state = STATE_PAUSED;
      this.emitState(STATE_PAUSED);
      return;
    }
    if (next === 'stopped') {
      this.state = STATE_STOPPED;
      this.emitState(STATE_STOPPED);
      return;
    }
    if (next === 'completed') {
      this.state = STATE_PAUSED;
      this.emitState(STATE_PAUSED);
    }
  }

  private onNativeError(errorCode: number): void {
    const message: string = `Playback failed (code ${errorCode.toString()})`;
    if (this.pendingCreate !== undefined) {
      const classified: string = errorCode === 5400103
        ? `read-failed: ${message}`
        : `unsupported-format: ${message}`;
      this.failPrepare(classified);
      return;
    }
    this.state = STATE_PAUSED;
    this.emitState(STATE_PAUSED);
    const payload = new NativeAudioPlayerEventPayload(this.id, 'error');
    payload.error = message;
    this.emit(payload);
  }

  private onNativeEndOfStream(): void {
    if (this.released) {
      return;
    }
    this.state = STATE_PAUSED;
    this.emitState(STATE_PAUSED);
    this.emit(new NativeAudioPlayerEventPayload(this.id, 'end'));
  }

  private onNativeInterrupt(event: audio.InterruptEvent): void {
    if (this.released) {
      return;
    }
    if (event.eventType === audio.InterruptType.INTERRUPT_TYPE_BEGIN) {
      this.emitInterruption(event.hintType === audio.InterruptHint.INTERRUPT_HINT_DUCK ? 'duck' : 'pause');
      return;
    }
    if (event.hintType === audio.InterruptHint.INTERRUPT_HINT_RESUME) {
      this.emitInterruption('resume');
      return;
    }
    if (event.hintType === audio.InterruptHint.INTERRUPT_HINT_DUCK) {
      this.emitInterruption('unduck');
    }
  }

  private emitInterruption(interruption: string): void {
    const payload = new NativeAudioPlayerEventPayload(this.id, 'state');
    payload.state = this.state;
    payload.interruption = interruption;
    this.emit(payload);
  }

  private onNativeTimeUpdate(time: number): void {
    if (this.released || this.state !== STATE_PLAYING) {
      return;
    }
    const now: number = Date.now();
    if (now - this.lastProgressAt < this.progressIntervalMs) {
      return;
    }
    this.lastProgressAt = now;
    const payload = new NativeAudioPlayerEventPayload(this.id, 'progress');
    payload.state = this.state;
    payload.positionMs = Math.round(time);
    payload.durationMs = this.durationMs();
    this.emit(payload);
  }

  private failPrepare(error: string): void {
    this.finishPrepare(error);
    this.release();
    this.onTerminal?.();
  }

  private finishPrepare(error: string): void {
    const callback = this.pendingCreate;
    this.pendingCreate = undefined;
    if (callback !== undefined) {
      callback(error);
    }
  }

  private durationMs(): number {
    const player = this.avPlayer;
    if (this.released || player === undefined || this.state === STATE_LOADING) {
      return 0;
    }
    const duration: number = player.duration;
    return Number.isFinite(duration) ? Math.round(duration) : 0;
  }

  private emitState(state: string): void {
    const player = this.avPlayer;
    const payload = new NativeAudioPlayerEventPayload(this.id, 'state');
    payload.state = state;
    payload.positionMs = this.state === STATE_STOPPED || player === undefined
      ? 0
      : Math.round(player.currentTime);
    payload.durationMs = this.durationMs();
    this.emit(payload);
  }

  private emit(payload: NativeAudioPlayerEventPayload): void {
    this.context.sendGlobalEvent(AudioModule.EVENT_NAME, [payload]);
  }

  private closeFile(): void {
    const file = this.file;
    this.file = undefined;
    if (file !== undefined) {
      try {
        fs.closeSync(file);
      } catch (_error) {
      }
    }
  }

  private messageOf(error: Object, fallback: string): string {
    return error instanceof Error && error.message.length > 0 ? error.message : fallback;
  }
}

/** Owns the players created by one Lynx NativeModule instance. */
class NativeAudioPlayerController {
  private readonly players: Map<string, NativeAudioPlayerHandle> = new Map();

  async create(options: NativeAudioPlayerOptions, callback: (error: string) => void, context: LynxContext): Promise<void> {
    if (!new RegExp('^[A-Za-z0-9._-]{1,128}$').test(options.id)) {
      callback('Invalid AudioPlayer ID');
      return;
    }
    if (this.players.has(options.id)) {
      callback('AudioPlayer ID already exists');
      return;
    }
    const uri: string = options.uri.trim();
    if (!uri.startsWith('file://')) {
      callback('AudioPlayer only supports local file:// sources');
      return;
    }
    if (!['media', 'ambient', 'alarm', 'notification'].includes(options.usage)) {
      callback('Invalid AudioPlayer usage');
      return;
    }
    const progressIntervalMs: number = options.progressIntervalMs;
    if (progressIntervalMs < 50 || progressIntervalMs > 10000) {
      callback('progressIntervalMs must be between 50 and 10000');
      return;
    }

    const handle = new NativeAudioPlayerHandle(
      options.id,
      options.usage,
      progressIntervalMs,
      options.autoPlay,
      context,
    );
    handle.pendingCreate = callback;
    handle.onTerminal = (): void => {
      this.players.delete(options.id);
    };
    this.players.set(options.id, handle);
    const error: string = await handle.create(options);
    if (error.length > 0) {
      this.players.delete(options.id);
      const pending = handle.pendingCreate;
      handle.pendingCreate = undefined;
      handle.release();
      if (pending !== undefined) {
        pending(error);
      }
      return;
    }
  }

  play(id: string, callback: (error: string) => void): void {
    const handle = this.players.get(id);
    if (handle === undefined) {
      callback('Unknown AudioPlayer ID');
      return;
    }
    handle.play(callback);
  }

  pause(id: string, callback: (error: string) => void): void {
    const handle = this.players.get(id);
    if (handle === undefined) {
      callback('Unknown AudioPlayer ID');
      return;
    }
    handle.pause(callback);
  }

  seek(id: string, positionMs: number, callback: (error: string) => void): void {
    const handle = this.players.get(id);
    if (handle === undefined) {
      callback('Unknown AudioPlayer ID');
      return;
    }
    handle.seek(positionMs, callback);
  }

  stop(id: string, callback: (error: string) => void): void {
    const handle = this.players.get(id);
    if (handle === undefined) {
      callback('Unknown AudioPlayer ID');
      return;
    }
    handle.stop(callback);
  }

  release(id: string, callback: (error: string) => void): void {
    const handle = this.players.get(id);
    if (handle === undefined) {
      callback('Unknown AudioPlayer ID');
      return;
    }
    this.players.delete(id);
    handle.release();
    callback('');
  }

  setRate(id: string, rate: number, callback: (error: string) => void): void {
    const handle = this.players.get(id);
    if (handle === undefined) {
      callback('Unknown AudioPlayer ID');
      return;
    }
    handle.setRate(rate, callback);
  }

  setVolume(id: string, volume: number, callback: (error: string) => void): void {
    const handle = this.players.get(id);
    if (handle === undefined) {
      callback('Unknown AudioPlayer ID');
      return;
    }
    handle.setVolume(volume, callback);
  }

  getProps(id: string, callback: (resultJSON: string) => void): void {
    const handle = this.players.get(id);
    if (handle === undefined) {
      callback('{"error":"Unknown AudioPlayer ID"}');
      return;
    }
    handle.getProps(callback);
  }

  destroy(): void {
    for (const handle of this.players.values()) {
      handle.release();
    }
    this.players.clear();
  }
}

class AudioPlayerLifecycleClient extends LynxViewClient {
  private readonly controller: NativeAudioPlayerController;

  constructor(controller: NativeAudioPlayerController) {
    super();
    this.controller = controller;
  }

  override onDestroy(): void {
    this.controller.destroy();
  }
}

class AudioRecorderLifecycleClient extends LynxViewClient {
  private readonly controller: NativeAudioRecorderController;

  constructor(controller: NativeAudioRecorderController) {
    super();
    this.controller = controller;
  }

  override onDestroy(): void {
    this.controller.destroy();
  }
}


export interface NativeAudioRecorderOptions {
  id: string;
  durationLimitMs: number;
  progressIntervalMs: number;
}

class NativeAudioRecorderEventPayload {
  id: string;
  type: string;
  state: string = '';
  durationMs: number = 0;
  uri: string = '';
  sizeBytes: number | null = null;
  error: string = '';

  constructor(id: string, type: string) {
    this.id = id;
    this.type = type;
  }
}

const REC_STATE_IDLE: string = 'idle';
const REC_STATE_RECORDING: string = 'recording';
const REC_STATE_PAUSED: string = 'paused';
const REC_STATE_STOPPED: string = 'stopped';
const REC_STATE_FAILED: string = 'failed';

/**
 * Owns one AVRecorder plus its open fd; the recorded duration is tracked
 * from wall-clock time because AVRecorder reports none. The microphone
 * permission is checked (never prompted) before every start.
 */
class NativeAudioRecorderHandle {
  readonly id: string;
  readonly durationLimitMs: number;
  readonly progressIntervalMs: number;
  readonly context: LynxContext;
  readonly abilityContext: common.UIAbilityContext;
  readonly atManager: abilityAccessCtrl.AtManager;

  state: string = REC_STATE_IDLE;
  released: boolean = false;
  delivered: boolean = false;
  deliveredUri: string | null = null;
  deliveredDurationMs: number = 0;
  failure: string | null = null;

  private recorder: media.AVRecorder | undefined = undefined;
  private file: fs.File | undefined = undefined;
  private recordingPath: string | null = null;
  private recordedMs: number = 0;
  private segmentStartAt: number = 0;
  private tickerId: number = -1;

  constructor(
    id: string,
    durationLimitMs: number,
    progressIntervalMs: number,
    context: LynxContext,
    abilityContext: common.UIAbilityContext,
  ) {
    this.id = id;
    this.durationLimitMs = durationLimitMs;
    this.progressIntervalMs = progressIntervalMs;
    this.context = context;
    this.abilityContext = abilityContext;
    this.atManager = abilityAccessCtrl.createAtManager();
  }

  async start(callback: (error: string) => void): Promise<void> {
    if (this.state !== REC_STATE_IDLE && this.state !== REC_STATE_STOPPED) {
      callback('AudioRecorder has already been started');
      return;
    }
    const permissionError: string = await this.checkMicrophonePermission();
    if (permissionError.length > 0) {
      callback(permissionError);
      return;
    }
    try {
      await this.resetForNextTake();
      const file: fs.File = this.openRecordingFile();
      const recorder: media.AVRecorder = await media.createAVRecorder();
      this.recorder = recorder;
      this.file = file;
      this.installListeners(recorder);
      await recorder.prepare({
        profile: {
          audioBitrate: 128000,
          audioChannels: 1,
          audioCodec: media.CodecMimeType.AUDIO_AAC,
          audioSampleRate: 44100,
          fileFormat: media.ContainerFormatType.CFT_MPEG_4A,
        },
        url: `fd://${file.fd.toString()}`,
      });
      await recorder.start();
    } catch (error) {
      this.fail(this.messageOf(error, 'Unable to start the recording'));
      callback(this.failure as string);
      return;
    }
    this.recordedMs = 0;
    this.segmentStartAt = Date.now();
    this.state = REC_STATE_RECORDING;
    this.emitState();
    this.startTicker();
    callback('');
  }

  async pause(callback: (error: string) => void): Promise<void> {
    const recorder = this.recorder;
    if (this.state !== REC_STATE_RECORDING || recorder === undefined) {
      callback(this.state === REC_STATE_IDLE ? 'AudioRecorder has not been started' : '');
      return;
    }
    try {
      await recorder.pause();
    } catch (error) {
      this.fail(this.messageOf(error, 'Unable to pause the recording'));
      callback(this.failure as string);
      return;
    }
    this.stopTicker();
    this.recordedMs += Date.now() - this.segmentStartAt;
    this.state = REC_STATE_PAUSED;
    this.emitState();
    callback('');
  }

  async resume(callback: (error: string) => void): Promise<void> {
    const recorder = this.recorder;
    if (this.state !== REC_STATE_PAUSED || recorder === undefined) {
      callback(this.state === REC_STATE_IDLE ? 'AudioRecorder has not been started' : '');
      return;
    }
    try {
      await recorder.resume();
    } catch (error) {
      this.fail(this.messageOf(error, 'Unable to resume the recording'));
      callback(this.failure as string);
      return;
    }
    this.state = REC_STATE_RECORDING;
    this.segmentStartAt = Date.now();
    this.emitState();
    this.startTicker();
    callback('');
  }

  async stop(callback: (resultJSON: string) => void): Promise<void> {
    if (this.state !== REC_STATE_RECORDING && this.state !== REC_STATE_PAUSED) {
      callback(this.delivered ? this.resultJSON() : this.stopError());
      return;
    }
    const recorder = this.recorder;
    if (recorder === undefined) {
      callback(this.stopError());
      return;
    }
    try {
      await recorder.stop();
    } catch (error) {
      this.fail(this.messageOf(error, 'Unable to stop the recording'));
      callback(this.failure as string);
      return;
    }
    this.finishRecording();
    callback(this.resultJSON());
  }

  async cancel(callback: (error: string) => void): Promise<void> {
    const recorder = this.recorder;
    if (recorder !== undefined) {
      try {
        if (this.state === REC_STATE_RECORDING || this.state === REC_STATE_PAUSED) {
          await recorder.stop();
        }
      } catch (_error) {
      }
    }
    this.stopTicker();
    await this.releaseRecorder();
    if (this.recordingPath !== null) {
      this.deleteIfExists(this.recordingPath);
    }
    this.recordingPath = null;
    this.recordedMs = 0;
    this.delivered = false;
    this.deliveredUri = null;
    this.state = REC_STATE_IDLE;
    callback('');
  }

  getProps(callback: (resultJSON: string) => void): void {
    callback(JSON.stringify({
      state: this.state,
      durationMs: this.durationMs(),
      uri: this.deliveredUri,
    }));
  }

  async release(): Promise<void> {
    this.stopTicker();
    await this.releaseRecorder();
    if (!this.delivered && this.recordingPath !== null) {
      this.deleteIfExists(this.recordingPath);
    }
    this.recordingPath = null;
    this.state = REC_STATE_STOPPED;
  }

  private async resetForNextTake(): Promise<void> {
    if (this.recorder === undefined) {
      return;
    }
    await this.releaseRecorder();
    this.delivered = false;
    this.deliveredUri = null;
    this.failure = null;
  }

  private async releaseRecorder(): Promise<void> {
    const recorder = this.recorder;
    this.recorder = undefined;
    const file = this.file;
    this.file = undefined;
    if (recorder !== undefined) {
      try {
        await recorder.release();
      } catch (_error) {
      }
    }
    if (file !== undefined) {
      try {
        fs.closeSync(file);
      } catch (_error) {
      }
    }
  }

  private openRecordingFile(): fs.File {
    const root: string = `${this.abilityContext.cacheDir}/LynxFiles/recordings`;
    if (!fs.accessSync(root)) {
      fs.mkdirSync(root, true);
    }
    const path: string = `${root}/${this.id}.m4a`;
    this.deleteIfExists(path);
    this.recordingPath = path;
    return fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
  }

  private installListeners(recorder: media.AVRecorder): void {
    recorder.on('error', (error: BusinessError) => {
      if (this.released || this.recorder !== recorder) {
        return;
      }
      this.fail(`Recording failed (code ${error.code.toString()})`);
    });
  }

  /** Runs on every tick: throttled progress plus the duration cap. */
  private startTicker(): void {
    this.stopTicker();
    this.tickerId = setInterval(() => {
      if (this.state !== REC_STATE_RECORDING) {
        return;
      }
      this.emitProgress();
      if (this.durationLimitMs > 0 && this.durationMs() >= this.durationLimitMs) {
        this.autoStop().catch((_error: Error) => {
        });
      }
    }, this.progressIntervalMs);
  }

  private stopTicker(): void {
    if (this.tickerId >= 0) {
      clearInterval(this.tickerId);
      this.tickerId = -1;
    }
  }

  private async autoStop(): Promise<void> {
    const recorder = this.recorder;
    if (recorder === undefined) {
      return;
    }
    try {
      await recorder.stop();
    } catch (error) {
      this.fail(this.messageOf(error, 'Unable to stop the recording'));
      return;
    }
    this.finishRecording();
    const payload = new NativeAudioRecorderEventPayload(this.id, 'end');
    payload.uri = this.deliveredUri as string;
    payload.durationMs = this.deliveredDurationMs;
    this.emit(payload);
  }

  private finishRecording(): void {
    this.stopTicker();
    if (this.state === REC_STATE_RECORDING) {
      this.recordedMs += Date.now() - this.segmentStartAt;
    }
    this.state = REC_STATE_STOPPED;
    this.delivered = true;
    this.deliveredUri = fileUri.getUriFromPath(this.recordingPath as string);
    this.deliveredDurationMs = this.recordedMs;
    this.releaseRecorder().catch((_error: Error) => {
    });
    this.emitState();
  }

  private async checkMicrophonePermission(): Promise<string> {
    try {
      const bundleInfo = await bundleManager.getBundleInfoForSelf(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION,
      );
      const tokenID = bundleInfo.appInfo.accessTokenId;
      const status = await this.atManager.checkAccessToken(
        tokenID,
        'ohos.permission.MICROPHONE',
      );
      if (status !== abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
        return 'microphone permission is required (request it via the Permissions module)';
      }
      return '';
    } catch (_error) {
      return 'Unable to verify the microphone permission';
    }
  }

  private durationMs(): number {
    const extra: number = this.state === REC_STATE_RECORDING
      ? Date.now() - this.segmentStartAt
      : 0;
    return this.recordedMs + extra;
  }

  private resultJSON(): string {
    let sizeBytes: number | null = null;
    if (this.recordingPath !== null && fs.accessSync(this.recordingPath)) {
      sizeBytes = fs.statSync(this.recordingPath).size;
    }
    return JSON.stringify({
      uri: this.deliveredUri,
      durationMs: this.deliveredDurationMs,
      sizeBytes: sizeBytes,
    });
  }

  private stopError(): string {
    if (this.state === REC_STATE_FAILED && this.failure !== null) {
      return this.failure;
    }
    return 'AudioRecorder has not been started';
  }

  private fail(message: string): void {
    this.stopTicker();
    void this.releaseRecorder();
    if (this.recordingPath !== null) {
      this.deleteIfExists(this.recordingPath);
    }
    this.recordingPath = null;
    this.state = REC_STATE_FAILED;
    this.failure = message;
    this.emitState();
    const payload = new NativeAudioRecorderEventPayload(this.id, 'error');
    payload.error = message;
    this.emit(payload);
  }

  private emitProgress(): void {
    const payload = new NativeAudioRecorderEventPayload(this.id, 'progress');
    payload.state = REC_STATE_RECORDING;
    payload.durationMs = this.durationMs();
    this.emit(payload);
  }

  private emitState(): void {
    const payload = new NativeAudioRecorderEventPayload(this.id, 'state');
    payload.state = this.state;
    payload.durationMs = this.durationMs();
    this.emit(payload);
  }

  private emit(payload: NativeAudioRecorderEventPayload): void {
    this.context.sendGlobalEvent(AudioModule.RECORDER_EVENT_NAME, [payload]);
  }

  private deleteIfExists(path: string): void {
    if (fs.accessSync(path)) {
      fs.unlinkSync(path);
    }
  }

  private messageOf(error: Object, fallback: string): string {
    return error instanceof Error && error.message.length > 0 ? error.message : fallback;
  }
}

/** Owns the recorders created by one Lynx NativeModule instance. */
class NativeAudioRecorderController {
  private readonly recorders: Map<string, NativeAudioRecorderHandle> = new Map();
  private readonly abilityContext: common.UIAbilityContext;

  constructor(abilityContext: common.UIAbilityContext) {
    this.abilityContext = abilityContext;
  }

  async create(
    options: NativeAudioRecorderOptions,
    callback: (error: string) => void,
    context: LynxContext,
  ): Promise<void> {
    if (!new RegExp('^[A-Za-z0-9._-]{1,128}$').test(options.id)) {
      callback('Invalid AudioRecorder ID');
      return;
    }
    if (this.recorders.has(options.id)) {
      callback('AudioRecorder ID already exists');
      return;
    }
    if (options.durationLimitMs !== 0
      && (options.durationLimitMs < 100 || options.durationLimitMs > 600000)) {
      callback('durationLimitMs must be between 100 and 600000, or 0 to disable');
      return;
    }
    if (options.progressIntervalMs < 50 || options.progressIntervalMs > 10000) {
      callback('progressIntervalMs must be between 50 and 10000');
      return;
    }
    const handle = new NativeAudioRecorderHandle(
      options.id,
      options.durationLimitMs,
      options.progressIntervalMs,
      context,
      this.abilityContext,
    );
    this.recorders.set(options.id, handle);
    callback('');
  }

  async start(id: string, callback: (error: string) => void): Promise<void> {
    await this.withHandle(id, callback, handle => handle.start(callback));
  }

  async pause(id: string, callback: (error: string) => void): Promise<void> {
    await this.withHandle(id, callback, handle => handle.pause(callback));
  }

  async resume(id: string, callback: (error: string) => void): Promise<void> {
    await this.withHandle(id, callback, handle => handle.resume(callback));
  }

  async stop(id: string, callback: (resultJSON: string) => void): Promise<void> {
    await this.withHandle(id, callback, handle => handle.stop(callback));
  }

  async cancel(id: string, callback: (error: string) => void): Promise<void> {
    const handle = this.recorders.get(id);
    if (handle === undefined) {
      callback('Unknown AudioRecorder ID');
      return;
    }
    this.recorders.delete(id);
    await handle.cancel(callback);
  }

  getProps(id: string, callback: (resultJSON: string) => void): void {
    const handle = this.recorders.get(id);
    if (handle === undefined) {
      callback('{"error":"Unknown AudioRecorder ID"}');
      return;
    }
    handle.getProps(callback);
  }

  async release(id: string, callback: (error: string) => void): Promise<void> {
    const handle = this.recorders.get(id);
    if (handle === undefined) {
      callback('Unknown AudioRecorder ID');
      return;
    }
    this.recorders.delete(id);
    await handle.release();
    callback('');
  }

  private async withHandle(
    id: string,
    callback: (error: string) => void,
    action: (handle: NativeAudioRecorderHandle) => Promise<void>,
  ): Promise<void> {
    const handle = this.recorders.get(id);
    if (handle === undefined) {
      callback('Unknown AudioRecorder ID');
      return;
    }
    await action(handle);
  }

  async destroy(): Promise<void> {
    for (const handle of this.recorders.values()) {
      handle.released = true;
      await handle.release();
    }
    this.recorders.clear();
  }
}

/** Local-file audio playback and microphone recording exported to Lynx as Audio. */
export class AudioModule extends LynxModule {
  static readonly NAME: string = 'Audio';
  static readonly EVENT_NAME: string = 'audioPlayer';
  static readonly RECORDER_EVENT_NAME: string = 'audioRecorder';
  private readonly controller: NativeAudioPlayerController;
  private readonly recorderController: NativeAudioRecorderController;

  constructor(context: LynxContext, param?: Object) {
    super(context, param);
    this.controller = new NativeAudioPlayerController();
    this.recorderController = new NativeAudioRecorderController(
      getContext(this) as common.UIAbilityContext,
    );
    context.getLynxViewClient()?.push(new AudioPlayerLifecycleClient(this.controller));
    context.getLynxViewClient()?.push(new AudioRecorderLifecycleClient(this.recorderController));
  }

  async create(options: NativeAudioPlayerOptions, callback: (error: string) => void): Promise<void> {
    await this.controller.create(options, callback, this.context);
  }

  play(id: string, callback: (error: string) => void): void {
    this.controller.play(id, callback);
  }

  pause(id: string, callback: (error: string) => void): void {
    this.controller.pause(id, callback);
  }

  seek(id: string, positionMs: number, callback: (error: string) => void): void {
    this.controller.seek(id, positionMs, callback);
  }

  stop(id: string, callback: (error: string) => void): void {
    this.controller.stop(id, callback);
  }

  release(id: string, callback: (error: string) => void): void {
    this.controller.release(id, callback);
  }

  setRate(id: string, rate: number, callback: (error: string) => void): void {
    this.controller.setRate(id, rate, callback);
  }

  setVolume(id: string, volume: number, callback: (error: string) => void): void {
    this.controller.setVolume(id, volume, callback);
  }

  getProps(id: string, callback: (resultJSON: string) => void): void {
    this.controller.getProps(id, callback);
  }

  async recorderCreate(options: NativeAudioRecorderOptions, callback: (error: string) => void): Promise<void> {
    await this.recorderController.create(options, callback, this.context);
  }

  async recorderStart(id: string, callback: (error: string) => void): Promise<void> {
    await this.recorderController.start(id, callback);
  }

  async recorderPause(id: string, callback: (error: string) => void): Promise<void> {
    await this.recorderController.pause(id, callback);
  }

  async recorderResume(id: string, callback: (error: string) => void): Promise<void> {
    await this.recorderController.resume(id, callback);
  }

  async recorderStop(id: string, callback: (resultJSON: string) => void): Promise<void> {
    await this.recorderController.stop(id, callback);
  }

  async recorderCancel(id: string, callback: (error: string) => void): Promise<void> {
    await this.recorderController.cancel(id, callback);
  }

  recorderGetProps(id: string, callback: (resultJSON: string) => void): void {
    this.recorderController.getProps(id, callback);
  }

  async recorderRelease(id: string, callback: (error: string) => void): Promise<void> {
    await this.recorderController.release(id, callback);
  }
}
