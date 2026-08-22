import {
  decodeNativeEnvelope,
  requireNativeModule,
} from './bridge.generated.js';

export * from './native.generated.js';

export type DownloadState =
  | 'queued'
  | 'running'
  | 'paused'
  | 'completed'
  | 'failed'
  | 'cancelled';

export type DownloadExecutionMode = 'in-app' | 'android-foreground-service';

export type DownloadPlatform = 'android' | 'ios' | 'harmony';

export interface AndroidForegroundServiceOptions {
  /** Enables an Android dataSync foreground service. Defaults to false. */
  enabled?: boolean;
  /** Foreground notification title, at most 80 characters. */
  notificationTitle?: string;
  /** Foreground notification body, at most 160 characters. */
  notificationText?: string;
}

export interface DownloadPlatformOptions {
  android?: {
    /** Ignored by non-Android hosts. */
    foregroundService?: AndroidForegroundServiceOptions;
  };
}

export interface DownloadOptions {
  /** HTTP(S) source. Production hosts may reject cleartext HTTP. */
  url: string;
  /** Safe destination basename. A name is derived from the URL when omitted. */
  fileName?: string;
  /** Request headers. Range and hop-by-hop headers are managed natively. */
  headers?: Record<string, string>;
  /** Minimum gap between progress events; 100..10000, defaults to 250. */
  progressIntervalMs?: number;
  /**
   * Persists task metadata and partial progress in app-private storage.
   * Interrupted tasks are restored as paused and require an explicit resume().
   * Defaults to false.
   */
  persistProgress?: boolean;
  /** Optional platform-specific execution capabilities. */
  platform?: DownloadPlatformOptions;
}

export interface DownloadTask {
  id: string;
  url: string;
  fileName: string;
  state: DownloadState;
  executionMode: DownloadExecutionMode;
  persistProgress: boolean;
  bytesDownloaded: number;
  totalBytes: number | null;
  fileUri: string | null;
  error: string | null;
  createdAt: number;
  updatedAt: number;
}

export interface DownloadManagerCapabilities {
  platform: DownloadPlatform;
  executionModes: DownloadExecutionMode[];
  /** Whether paused transfers continue from partial bytes when supported upstream. */
  byteRangeResume: boolean;
  /** Whether opt-in persisted tasks are restored, paused, after process death. */
  processRestartRecovery: boolean;
}

export interface DownloadProgressEvent {
  type: 'progress';
  task: DownloadTask;
}

export interface DownloadStateEvent {
  type: 'state';
  task: DownloadTask;
}

export interface DownloadEventMap {
  progress: DownloadProgressEvent;
  state: DownloadStateEvent;
}

export type DownloadEventType = keyof DownloadEventMap;

type DownloadListener<T extends DownloadEventType> = (
  event: DownloadEventMap[T],
) => void;

type UntypedDownloadListener = (
  event: DownloadEventMap[DownloadEventType],
) => void;

interface DownloadEnvelope {
  value?: unknown;
  error?: unknown;
}

interface DownloadEventPayload {
  type?: unknown;
  task?: unknown;
}

interface NativeDownloadOptions {
  id: string;
  url: string;
  fileName: string;
  headers: Record<string, string>;
  progressIntervalMs: number;
  persistProgress: boolean;
  androidForegroundService: boolean;
  notificationTitle: string;
  notificationText: string;
}

export const DOWNLOAD_MANAGER_EVENT = 'downloadManager';

const DOWNLOAD_STATES: readonly DownloadState[] = [
  'queued',
  'running',
  'paused',
  'completed',
  'failed',
  'cancelled',
];
const EXECUTION_MODES: readonly DownloadExecutionMode[] = [
  'in-app',
  'android-foreground-service',
];
const PLATFORMS: readonly DownloadPlatform[] = ['android', 'ios', 'harmony'];
const HEADER_NAME = /^[!#$%&'*+.^_`|~0-9A-Za-z-]+$/;
const DOWNLOAD_ID = /^[A-Za-z0-9._-]{1,128}$/;
const RESERVED_HEADERS = new Set([
  'accept-encoding',
  'connection',
  'content-length',
  'host',
  'if-range',
  'range',
  'transfer-encoding',
]);
const listeners = new Map<DownloadEventType, Set<UntypedDownloadListener>>();
let nextDownloadID = 0;
let listeningForEvents = false;

function requireDownloadManagerModule() {
  'background only';
  return requireNativeModule();
}

function isObject(value: unknown): value is Record<string, unknown> {
  'background only';
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function isFiniteSafeInteger(value: unknown): value is number {
  'background only';
  return typeof value === 'number' && Number.isSafeInteger(value) && value >= 0;
}

function isDownloadState(value: unknown): value is DownloadState {
  'background only';
  return (
    typeof value === 'string' &&
    DOWNLOAD_STATES.includes(value as DownloadState)
  );
}

function isExecutionMode(value: unknown): value is DownloadExecutionMode {
  'background only';
  return (
    typeof value === 'string' &&
    EXECUTION_MODES.includes(value as DownloadExecutionMode)
  );
}

function decodeTask(value: unknown): DownloadTask {
  'background only';
  if (!isObject(value)) {
    throw new Error('DownloadManager returned an invalid task');
  }
  const task = value as Partial<DownloadTask>;
  if (
    typeof task.id !== 'string' ||
    !DOWNLOAD_ID.test(task.id) ||
    typeof task.url !== 'string' ||
    typeof task.fileName !== 'string' ||
    !isDownloadState(task.state) ||
    !isExecutionMode(task.executionMode) ||
    typeof task.persistProgress !== 'boolean' ||
    !isFiniteSafeInteger(task.bytesDownloaded) ||
    (task.totalBytes !== null && !isFiniteSafeInteger(task.totalBytes)) ||
    (task.fileUri !== null && typeof task.fileUri !== 'string') ||
    (task.error !== null && typeof task.error !== 'string') ||
    !isFiniteSafeInteger(task.createdAt) ||
    !isFiniteSafeInteger(task.updatedAt)
  ) {
    throw new Error('DownloadManager returned an invalid task');
  }
  return task as DownloadTask;
}

function decodeCapabilities(value: unknown): DownloadManagerCapabilities {
  'background only';
  if (!isObject(value)) {
    throw new Error('DownloadManager returned invalid capabilities');
  }
  const platform = value.platform;
  const executionModes = value.executionModes;
  if (
    typeof platform !== 'string' ||
    !PLATFORMS.includes(platform as DownloadPlatform) ||
    !Array.isArray(executionModes) ||
    !executionModes.every(isExecutionMode) ||
    typeof value.byteRangeResume !== 'boolean' ||
    typeof value.processRestartRecovery !== 'boolean'
  ) {
    throw new Error('DownloadManager returned invalid capabilities');
  }
  return {
    platform: platform as DownloadPlatform,
    executionModes: [...executionModes],
    byteRangeResume: value.byteRangeResume,
    processRestartRecovery: value.processRestartRecovery,
  };
}

function invoke<T>(
  action: (callback: (result: string) => void) => void,
  decode: (value: unknown) => T,
): Promise<T> {
  'background only';
  return new Promise((resolve, reject) => {
    try {
      action((resultValue) => {
        'background only';
        try {
          const envelope = decodeNativeEnvelope(
            resultValue,
            'DownloadManager',
          ) as DownloadEnvelope;
          if (typeof envelope.error === 'string' && envelope.error.length > 0) {
            reject(new Error(envelope.error));
            return;
          }
          resolve(decode(envelope.value));
        } catch (error) {
          reject(error instanceof Error ? error : new Error(String(error)));
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
    .addListener(DOWNLOAD_MANAGER_EVENT, dispatchEvent);
}

function dispatchEvent(value: unknown): void {
  'background only';
  if (!isObject(value)) return;
  const payload = value as DownloadEventPayload;
  if (payload.type !== 'progress' && payload.type !== 'state') return;
  try {
    const event = {
      type: payload.type,
      task: decodeTask(payload.task),
    } as DownloadEventMap[DownloadEventType];
    for (const listener of listeners.get(payload.type) ?? []) {
      try {
        listener(event);
      } catch {
        // One consumer must not prevent the remaining task observers.
      }
    }
  } catch {
    // Native events are untrusted transport data; malformed updates are ignored.
  }
}

function deriveFileName(url: string): string {
  'background only';
  const withoutFragment = url.split('#', 1)[0] ?? url;
  const withoutQuery = withoutFragment.split('?', 1)[0] ?? withoutFragment;
  const candidate = withoutQuery.slice(withoutQuery.lastIndexOf('/') + 1);
  let decoded = candidate;
  try {
    decoded = decodeURIComponent(candidate);
  } catch {
    // Keep the encoded path segment when percent escapes are malformed.
  }
  let sanitized = '';
  for (const character of decoded) {
    const code = character.charCodeAt(0);
    sanitized +=
      code < 0x20 || code === 0x7f || '\\/:*?"<>|'.includes(character)
        ? '_'
        : character;
  }
  sanitized = sanitized.trim();
  if (sanitized.length === 0 || sanitized === '.' || sanitized === '..') {
    return 'download';
  }
  return sanitized.slice(0, 128);
}

function normalizeFileName(value: unknown, url: string): string {
  'background only';
  const fileName = value === undefined ? deriveFileName(url) : value;
  if (
    typeof fileName !== 'string' ||
    fileName.length < 1 ||
    fileName.length > 128 ||
    fileName.trim() !== fileName ||
    fileName === '.' ||
    fileName === '..' ||
    hasUnsafeFileNameCharacter(fileName)
  ) {
    throw new Error(
      'Download fileName must be a safe basename up to 128 chars',
    );
  }
  return fileName;
}

function hasUnsafeFileNameCharacter(value: string): boolean {
  'background only';
  for (const character of value) {
    const code = character.charCodeAt(0);
    if (
      code < 0x20 ||
      code === 0x7f ||
      character === '/' ||
      character === '\\'
    ) {
      return true;
    }
  }
  return false;
}

function normalizeHeaders(value: unknown): Record<string, string> {
  'background only';
  if (value === undefined) return {};
  if (!isObject(value)) {
    throw new Error('Download headers must be a string record');
  }
  const entries = Object.entries(value);
  if (entries.length > 64) {
    throw new Error('Download headers must contain at most 64 fields');
  }
  const headers: Record<string, string> = {};
  for (const [name, headerValue] of entries) {
    if (!HEADER_NAME.test(name)) {
      throw new Error(`Invalid download header name: ${name}`);
    }
    if (RESERVED_HEADERS.has(name.toLowerCase())) {
      throw new Error(`DownloadManager owns the ${name} header`);
    }
    if (
      typeof headerValue !== 'string' ||
      headerValue.length > 8192 ||
      /[\r\n]/.test(headerValue)
    ) {
      throw new Error(`Invalid value for download header: ${name}`);
    }
    headers[name] = headerValue;
  }
  return headers;
}

function normalizeOptions(options: DownloadOptions): NativeDownloadOptions {
  'background only';
  if (!isObject(options)) {
    throw new Error('Download options are required');
  }
  const url = options.url;
  if (
    typeof url !== 'string' ||
    url.length > 8192 ||
    !/^https?:\/\/[^\s]+$/i.test(url)
  ) {
    throw new Error('Download URL must use http:// or https://');
  }
  const fileName = normalizeFileName(options.fileName, url);
  const progressIntervalMs = options.progressIntervalMs ?? 250;
  if (
    !Number.isInteger(progressIntervalMs) ||
    progressIntervalMs < 100 ||
    progressIntervalMs > 10_000
  ) {
    throw new Error('progressIntervalMs must be an integer from 100 to 10000');
  }

  const persistProgress = options.persistProgress ?? false;
  if (typeof persistProgress !== 'boolean') {
    throw new Error('persistProgress must be a boolean');
  }

  const foreground = options.platform?.android?.foregroundService;
  if (foreground !== undefined && !isObject(foreground)) {
    throw new Error('android.foregroundService must be an object');
  }
  const enabled = foreground?.enabled ?? false;
  if (typeof enabled !== 'boolean') {
    throw new Error('android.foregroundService.enabled must be a boolean');
  }
  const notificationTitle =
    foreground?.notificationTitle ?? `Downloading ${fileName}`;
  const notificationText =
    foreground?.notificationText ?? 'Download in progress';
  if (
    typeof notificationTitle !== 'string' ||
    notificationTitle.length < 1 ||
    notificationTitle.length > 80
  ) {
    throw new Error('notificationTitle must contain 1 to 80 characters');
  }
  if (
    typeof notificationText !== 'string' ||
    notificationText.length < 1 ||
    notificationText.length > 160
  ) {
    throw new Error('notificationText must contain 1 to 160 characters');
  }

  nextDownloadID += 1;
  return {
    id: `dl-${Date.now().toString(36)}-${nextDownloadID.toString(36)}`,
    url,
    fileName,
    headers: normalizeHeaders(options.headers),
    progressIntervalMs,
    persistProgress,
    androidForegroundService: enabled,
    notificationTitle,
    notificationText,
  };
}

function normalizeID(id: string): string {
  'background only';
  if (typeof id !== 'string' || !DOWNLOAD_ID.test(id)) {
    throw new Error('Invalid download task ID');
  }
  return id;
}

function decodeOptionalTask(value: unknown): DownloadTask | null {
  'background only';
  return value === null ? null : decodeTask(value);
}

function decodeTasks(value: unknown): DownloadTask[] {
  'background only';
  if (!Array.isArray(value)) {
    throw new Error('DownloadManager returned an invalid task list');
  }
  return value.map(decodeTask);
}

function decodeVoid(value: unknown): void {
  'background only';
  if (value !== null && value !== undefined) {
    throw new Error('DownloadManager returned an invalid acknowledgement');
  }
}

export const downloadManager = {
  getCapabilities(): Promise<DownloadManagerCapabilities> {
    'background only';
    return invoke(
      (callback) => requireDownloadManagerModule().getCapabilities(callback),
      decodeCapabilities,
    );
  },

  enqueue(options: DownloadOptions): Promise<DownloadTask> {
    'background only';
    const normalized = normalizeOptions(options);
    return invoke(
      (callback) =>
        requireDownloadManagerModule().enqueue(normalized, callback),
      decodeTask,
    );
  },

  pause(id: string): Promise<DownloadTask> {
    'background only';
    const normalized = normalizeID(id);
    return invoke(
      (callback) => requireDownloadManagerModule().pause(normalized, callback),
      decodeTask,
    );
  },

  resume(id: string): Promise<DownloadTask> {
    'background only';
    const normalized = normalizeID(id);
    return invoke(
      (callback) => requireDownloadManagerModule().resume(normalized, callback),
      decodeTask,
    );
  },

  cancel(id: string): Promise<DownloadTask> {
    'background only';
    const normalized = normalizeID(id);
    return invoke(
      (callback) => requireDownloadManagerModule().cancel(normalized, callback),
      decodeTask,
    );
  },

  remove(id: string, options: { deleteFile?: boolean } = {}): Promise<void> {
    'background only';
    const normalized = normalizeID(id);
    const deleteFile = options.deleteFile ?? false;
    if (typeof deleteFile !== 'boolean') {
      throw new Error('deleteFile must be a boolean');
    }
    return invoke(
      (callback) =>
        requireDownloadManagerModule().remove(normalized, deleteFile, callback),
      decodeVoid,
    );
  },

  getTask(id: string): Promise<DownloadTask | null> {
    'background only';
    const normalized = normalizeID(id);
    return invoke(
      (callback) =>
        requireDownloadManagerModule().getTask(normalized, callback),
      decodeOptionalTask,
    );
  },

  listTasks(): Promise<DownloadTask[]> {
    'background only';
    return invoke(
      (callback) => requireDownloadManagerModule().listTasks(callback),
      decodeTasks,
    );
  },

  addEventListener<T extends DownloadEventType>(
    type: T,
    listener: DownloadListener<T>,
  ): () => void {
    'background only';
    installEventListener();
    const typeListeners = listeners.get(type) ?? new Set();
    typeListeners.add(listener as UntypedDownloadListener);
    listeners.set(type, typeListeners);
    return () => {
      'background only';
      downloadManager.removeEventListener(type, listener);
    };
  },

  removeEventListener<T extends DownloadEventType>(
    type: T,
    listener: DownloadListener<T>,
  ): void {
    'background only';
    listeners.get(type)?.delete(listener as UntypedDownloadListener);
  },
};
