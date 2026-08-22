import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';
import { LynxContext, LynxModule, LynxViewClient } from '@lynx/lynx';
import BuildProfile from '../../../BuildProfile';

export interface NativeDownloadOptions {
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

class NativeDownloadValue {
  id: string;
  url: string;
  fileName: string;
  state: string;
  executionMode: string = 'in-app';
  persistProgress: boolean;
  bytesDownloaded: number;
  totalBytes: number | null;
  fileUri: string | null;
  error: string | null;
  createdAt: number;
  updatedAt: number;

  constructor(task: NativeDownloadTask) {
    this.id = task.id;
    this.url = task.url;
    this.fileName = task.fileName;
    this.state = task.state;
    this.persistProgress = task.persistProgress;
    this.bytesDownloaded = task.bytesDownloaded;
    this.totalBytes = task.totalBytes;
    this.fileUri = task.fileUri;
    this.error = task.error;
    this.createdAt = task.createdAt;
    this.updatedAt = task.updatedAt;
  }
}

class NativeDownloadCapabilities {
  platform: string = 'harmony';
  executionModes: Array<string> = ['in-app'];
  byteRangeResume: boolean = true;
  processRestartRecovery: boolean = true;
}

class NativeDownloadResult {
  value: Object | null;
  error: string;

  constructor(value: Object | null, error: string = '') {
    this.value = value;
    this.error = error;
  }
}

class NativeDownloadEventPayload {
  type: string;
  task: NativeDownloadValue;

  constructor(type: string, task: NativeDownloadTask) {
    this.type = type;
    this.task = new NativeDownloadValue(task);
  }
}

class NativeDownloadTask {
  readonly id: string;
  readonly url: string;
  readonly fileName: string;
  readonly headers: Record<string, string>;
  readonly progressIntervalMs: number;
  readonly persistProgress: boolean;
  readonly createdAt: number;

  state: string = 'queued';
  bytesDownloaded: number = 0;
  totalBytes: number | null = null;
  fileUri: string | null = null;
  error: string | null = null;
  rangeValidator: string | null = null;
  updatedAt: number;
  lastProgressEventAt: number = 0;
  generation: number = 0;
  requestedOffset: number = 0;
  responseAppend: boolean = false;
  responseRangeTotal: number | null = null;
  responsePrepared: boolean = false;
  responseUnsatisfiedRange: boolean = false;
  pendingResponseData: Array<ArrayBuffer> = [];
  pendingResponseBytes: number = 0;
  request: http.HttpRequest | undefined = undefined;
  file: fs.File | undefined = undefined;

  constructor(options: NativeDownloadOptions, createdAt: number = Date.now()) {
    this.id = options.id;
    this.url = options.url;
    this.fileName = options.fileName;
    this.headers = options.headers;
    this.progressIntervalMs = options.progressIntervalMs;
    this.persistProgress = options.persistProgress;
    this.createdAt = createdAt;
    this.updatedAt = createdAt;
  }
}

class PersistedDownloadTaskValue {
  version: number = 1;
  id: string = '';
  url: string = '';
  fileName: string = '';
  headers: Record<string, string> = {};
  progressIntervalMs: number = 250;
  persistProgress: boolean = true;
  state: string = 'paused';
  bytesDownloaded: number = 0;
  totalBytes: number | null = null;
  error: string | null = null;
  rangeValidator: string | null = null;
  createdAt: number = 0;
  updatedAt: number = 0;

  constructor(task?: NativeDownloadTask) {
    if (task === undefined) return;
    this.id = task.id;
    this.url = task.url;
    this.fileName = task.fileName;
    this.headers = task.headers;
    this.progressIntervalMs = task.progressIntervalMs;
    this.persistProgress = task.persistProgress;
    this.state = task.state;
    this.bytesDownloaded = task.bytesDownloaded;
    this.totalBytes = task.totalBytes;
    this.error = task.error;
    this.rangeValidator = task.rangeValidator;
    this.createdAt = task.createdAt;
    this.updatedAt = task.updatedAt;
  }
}

class RestoredDownloadOptions implements NativeDownloadOptions {
  id: string;
  url: string;
  fileName: string;
  headers: Record<string, string>;
  progressIntervalMs: number;
  persistProgress: boolean = true;
  androidForegroundService: boolean = false;
  notificationTitle: string = 'Download';
  notificationText: string = 'Download in progress';

  constructor(value: PersistedDownloadTaskValue) {
    this.id = value.id;
    this.url = value.url;
    this.fileName = value.fileName;
    this.headers = value.headers;
    this.progressIntervalMs = value.progressIntervalMs;
  }
}

/**
 * In-app streaming downloader shared by every HarmonyOS Lynx module instance
 * (mirrors the Android/iOS process-wide stores): tasks outlive the page that
 * created them, and events broadcast to every live page context.
 */
class NativeDownloadStore {
  private static readonly MAX_METADATA_BYTES: number = 1024 * 1024;
  private static readonly MAX_PENDING_HEADER_BYTES: number = 1024 * 1024;
  private static instance: NativeDownloadStore | undefined = undefined;

  static shared(abilityContext: common.UIAbilityContext): NativeDownloadStore {
    if (NativeDownloadStore.instance === undefined) {
      NativeDownloadStore.instance = new NativeDownloadStore();
    }
    NativeDownloadStore.instance.abilityContext = abilityContext;
    NativeDownloadStore.instance.loadPersistedTasksOnce();
    return NativeDownloadStore.instance;
  }

  private abilityContext: common.UIAbilityContext | undefined = undefined;
  private persistedTasksLoaded: boolean = false;
  private readonly contexts: Set<LynxContext> = new Set();
  private readonly tasks: Map<string, NativeDownloadTask> = new Map();

  attach(context: LynxContext): void {
    this.contexts.add(context);
  }

  detach(context: LynxContext): void {
    this.contexts.delete(context);
  }

  capabilities(callback: (resultJSON: string) => void): void {
    callback(this.result(new NativeDownloadCapabilities()));
  }

  enqueue(options: NativeDownloadOptions, callback: (resultJSON: string) => void): void {
    const validationError: string = this.validateOptions(options);
    if (validationError.length > 0) {
      callback(this.result(null, validationError));
      return;
    }
    if (this.tasks.has(options.id)) {
      callback(this.result(null, 'Download task ID already exists'));
      return;
    }
    const task = new NativeDownloadTask(options);
    this.tasks.set(task.id, task);
    try {
      this.persistTask(task);
      this.start(task);
      callback(this.result(new NativeDownloadValue(task)));
    } catch (error) {
      task.generation += 1;
      this.closeTransport(task);
      try {
        this.deleteIfExists(this.partialPath(task));
      } catch (_cleanupError) {
      }
      this.tasks.delete(task.id);
      this.deletePersistedTaskQuietly(task);
      callback(this.result(null, this.messageOf(error, 'Unable to start download')));
    }
  }

  pause(id: string, callback: (resultJSON: string) => void): void {
    const task = this.tasks.get(id);
    if (task === undefined) {
      callback(this.result(null, 'Unknown download task ID'));
      return;
    }
    if (task.state !== 'running' && task.state !== 'queued') {
      callback(this.result(null, 'Download task is not running'));
      return;
    }
    task.generation += 1;
    task.state = 'paused';
    task.error = null;
    task.updatedAt = Date.now();
    this.closeTransport(task);
    this.emit('state', task);
    callback(this.result(new NativeDownloadValue(task)));
  }

  resume(id: string, callback: (resultJSON: string) => void): void {
    const task = this.tasks.get(id);
    if (task === undefined) {
      callback(this.result(null, 'Unknown download task ID'));
      return;
    }
    if (task.state !== 'paused' && task.state !== 'failed') {
      callback(this.result(null, 'Only paused or failed downloads can resume'));
      return;
    }
    try {
      task.fileUri = null;
      task.error = null;
      task.state = 'queued';
      task.updatedAt = Date.now();
      this.start(task);
      callback(this.result(new NativeDownloadValue(task)));
    } catch (error) {
      task.generation += 1;
      this.closeTransport(task);
      task.state = 'failed';
      task.error = this.messageOf(error, 'Unable to resume download');
      task.updatedAt = Date.now();
      this.emit('state', task);
      callback(this.result(null, this.messageOf(error, 'Unable to resume download')));
    }
  }

  cancel(id: string, callback: (resultJSON: string) => void): void {
    const task = this.tasks.get(id);
    if (task === undefined) {
      callback(this.result(null, 'Unknown download task ID'));
      return;
    }
    if (task.state === 'completed') {
      callback(this.result(null, 'Completed downloads cannot be cancelled'));
      return;
    }
    if (task.state !== 'cancelled') {
      task.generation += 1;
      task.state = 'cancelled';
      task.bytesDownloaded = 0;
      task.fileUri = null;
      task.error = null;
      task.updatedAt = Date.now();
      this.closeTransport(task);
      this.deleteIfExists(this.partialPath(task));
      this.emit('state', task);
    }
    callback(this.result(new NativeDownloadValue(task)));
  }

  remove(id: string, deleteFile: boolean, callback: (resultJSON: string) => void): void {
    const task = this.tasks.get(id);
    if (task === undefined) {
      callback(this.result(null, 'Unknown download task ID'));
      return;
    }
    task.generation += 1;
    this.closeTransport(task);
    this.deleteIfExists(this.partialPath(task));
    if (deleteFile) {
      this.deleteIfExists(this.destinationPath(task));
    }
    try {
      this.deletePersistedTask(task);
    } catch (error) {
      callback(this.result(null, this.messageOf(error, 'Unable to remove persisted task')));
      return;
    }
    this.tasks.delete(id);
    callback(this.result(null));
  }

  getTask(id: string, callback: (resultJSON: string) => void): void {
    const task = this.tasks.get(id);
    callback(this.result(task === undefined ? null : new NativeDownloadValue(task)));
  }

  listTasks(callback: (resultJSON: string) => void): void {
    const values: Array<NativeDownloadValue> = Array.from(this.tasks.values())
      .sort((left: NativeDownloadTask, right: NativeDownloadTask) => left.createdAt - right.createdAt)
      .map((task: NativeDownloadTask) => new NativeDownloadValue(task));
    callback(this.result(values));
  }

  private start(task: NativeDownloadTask): void {
    this.ensureDirectory();
    const partial: string = this.partialPath(task);
    const partialSize: number = this.fileSize(partial);
    const offset: number = partialSize > 0 && task.rangeValidator !== null ? partialSize : 0;
    task.generation += 1;
    const generation: number = task.generation;
    const request = http.createHttp();
    task.request = request;
    task.file = undefined;
    task.requestedOffset = offset;
    task.responseAppend = false;
    task.responseRangeTotal = null;
    task.responsePrepared = false;
    task.responseUnsatisfiedRange = false;
    task.pendingResponseData = [];
    task.pendingResponseBytes = 0;
    task.bytesDownloaded = offset;
    if (offset === 0) task.totalBytes = null;
    task.state = 'running';
    task.error = null;
    task.updatedAt = Date.now();
    this.emit('state', task);

    request.once('headersReceive', (headers: Object) => {
      if (!this.isCurrent(task, generation)) return;
      try {
        this.prepareResponse(task, generation, headers as Record<string, string>);
        const pending: Array<ArrayBuffer> = task.pendingResponseData;
        task.pendingResponseData = [];
        task.pendingResponseBytes = 0;
        for (const data of pending) {
          if (!this.writeResponseData(task, generation, data)) break;
        }
      } catch (error) {
        this.fail(task, generation, this.messageOf(error, 'Invalid download response'));
        request.destroy();
      }
    });
    request.on('dataReceive', (data: ArrayBuffer) => {
      if (!this.isCurrent(task, generation)) return;
      if (!task.responsePrepared) {
        task.pendingResponseBytes += data.byteLength;
        if (task.pendingResponseBytes > NativeDownloadStore.MAX_PENDING_HEADER_BYTES) {
          this.fail(task, generation, 'Download body arrived before response headers');
          request.destroy();
          return;
        }
        task.pendingResponseData.push(data);
        return;
      }
      if (!this.writeResponseData(task, generation, data)) request.destroy();
    });

    const requestHeaders: Record<string, string> = {};
    for (const name of Object.keys(task.headers)) {
      requestHeaders[name] = task.headers[name];
    }
    requestHeaders['Accept-Encoding'] = 'identity';
    if (offset > 0) {
      requestHeaders['Range'] = `bytes=${offset}-`;
      requestHeaders['If-Range'] = task.rangeValidator as string;
    }
    request.requestInStream(task.url, {
      method: http.RequestMethod.GET,
      header: requestHeaders,
      expectDataType: http.HttpDataType.ARRAY_BUFFER,
      usingCache: false,
    }, (error: BusinessError, statusCode: number) => {
      request.off('dataReceive');
      if (!this.isCurrent(task, generation)) return;
      task.request = undefined;
      if (error) {
        this.fail(task, generation, this.messageOf(error, 'Download failed'));
        request.destroy();
        return;
      }
      if (statusCode === 416 && task.requestedOffset > 0 &&
        task.responseRangeTotal === task.requestedOffset) {
        try {
          this.complete(task, generation);
        } catch (moveError) {
          this.fail(task, generation, this.messageOf(moveError, 'Unable to save download'));
        }
        request.destroy();
        return;
      }
      if (statusCode < 200 || statusCode >= 300) {
        this.closeFile(task);
        this.deleteIfExists(this.partialPath(task));
        task.bytesDownloaded = 0;
        task.totalBytes = null;
        task.rangeValidator = null;
        this.fail(task, generation, `HTTP ${statusCode}`);
        request.destroy();
        return;
      }
      if (statusCode === 206 && !task.responseAppend) {
        this.closeFile(task);
        this.deleteIfExists(this.partialPath(task));
        task.bytesDownloaded = 0;
        task.totalBytes = null;
        task.rangeValidator = null;
        this.fail(task, generation, 'Server returned an invalid Content-Range');
        request.destroy();
        return;
      }
      if (statusCode !== 206 && task.responseAppend) {
        this.closeFile(task);
        this.deleteIfExists(this.partialPath(task));
        task.bytesDownloaded = 0;
        task.totalBytes = null;
        task.rangeValidator = null;
        this.fail(task, generation, 'Server returned an unexpected range response');
        request.destroy();
        return;
      }
      try {
        if (!task.responsePrepared) this.prepareResponse(task, generation, {});
        if (task.pendingResponseData.length > 0) {
          throw new Error('Download response headers were not received');
        }
        if (task.file === undefined) this.openResponseFile(task);
        this.closeFile(task);
        const actualSize: number = this.fileSize(this.partialPath(task));
        task.bytesDownloaded = actualSize;
        if (task.totalBytes !== null && actualSize !== task.totalBytes) {
          throw new Error('Downloaded byte count did not match Content-Length');
        }
        this.complete(task, generation);
      } catch (moveError) {
        this.fail(task, generation, this.messageOf(moveError, 'Unable to save download'));
      }
      request.destroy();
    });
  }

  private prepareResponse(
    task: NativeDownloadTask,
    generation: number,
    headers: Record<string, string>,
  ): void {
    if (!this.isCurrent(task, generation) || task.responsePrepared) return;
    const contentRange: string | null = this.headerValue(headers, 'content-range');
    const rangeStart: number | null = this.contentRangeStart(contentRange);
    const unsatisfiedTotal: number | null = this.unsatisfiedRangeTotal(contentRange);
    if (task.requestedOffset > 0 && contentRange !== null &&
      rangeStart === null && unsatisfiedTotal === null) {
      throw new Error('Server returned an invalid Content-Range');
    }
    if (task.requestedOffset > 0 && rangeStart !== null &&
      rangeStart !== task.requestedOffset) {
      throw new Error('Server returned an invalid Content-Range');
    }

    task.responseUnsatisfiedRange = task.requestedOffset > 0 && unsatisfiedTotal !== null;
    task.responseAppend = task.requestedOffset > 0 && rangeStart === task.requestedOffset;
    task.responseRangeTotal = task.responseUnsatisfiedRange
      ? unsatisfiedTotal
      : this.contentRangeTotal(contentRange);
    if (task.responseRangeTotal !== null && rangeStart !== null &&
      task.responseRangeTotal < rangeStart) {
      throw new Error('Server returned an invalid Content-Range');
    }
    task.responsePrepared = true;
    if (!task.responseUnsatisfiedRange) {
      if (!task.responseAppend) {
        task.bytesDownloaded = 0;
        task.totalBytes = null;
        task.rangeValidator = this.responseValidator(headers);
      }
      const length: number | null = this.contentLength(headers);
      task.totalBytes = task.responseRangeTotal !== null
        ? task.responseRangeTotal
        : this.addContentLength(length, task.responseAppend ? task.requestedOffset : 0);
    }
    task.updatedAt = Date.now();
    this.emit('progress', task);
  }

  private writeResponseData(
    task: NativeDownloadTask,
    generation: number,
    data: ArrayBuffer,
  ): boolean {
    if (!this.isCurrent(task, generation)) return false;
    if (task.responseUnsatisfiedRange) {
      return true;
    }
    try {
      let file: fs.File | undefined = task.file;
      if (file === undefined) file = this.openResponseFile(task);
      const count: number = fs.writeSync(file.fd, data);
      const downloaded: number = task.bytesDownloaded + count;
      if (!this.isSafeInteger(downloaded)) {
        throw new Error('Download exceeds the JavaScript safe integer limit');
      }
      if (task.totalBytes !== null && downloaded > task.totalBytes) {
        throw new Error('Downloaded byte count exceeded Content-Length');
      }
      task.bytesDownloaded = downloaded;
      task.updatedAt = Date.now();
      if (task.updatedAt - task.lastProgressEventAt >= task.progressIntervalMs) {
        task.lastProgressEventAt = task.updatedAt;
        this.emit('progress', task);
      }
      return true;
    } catch (error) {
      this.fail(task, generation, this.messageOf(error, 'Unable to write download'));
      return false;
    }
  }

  private complete(task: NativeDownloadTask, generation: number): void {
    if (!this.isCurrent(task, generation)) return;
    this.closeFile(task);
    const partial: string = this.partialPath(task);
    const downloaded: number = this.fileSize(partial);
    const destination: string = this.destinationPath(task);
    this.deleteIfExists(destination);
    fs.renameSync(partial, destination);
    task.bytesDownloaded = downloaded;
    task.totalBytes = downloaded;
    task.state = 'completed';
    task.fileUri = fileUri.getUriFromPath(destination);
    task.error = null;
    task.updatedAt = Date.now();
    this.emit('state', task);
  }

  private openResponseFile(task: NativeDownloadTask): fs.File {
    const flags: number = fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE |
      (task.responseAppend ? fs.OpenMode.APPEND : fs.OpenMode.TRUNC);
    const file: fs.File = fs.openSync(this.partialPath(task), flags);
    task.file = file;
    return file;
  }

  private fail(task: NativeDownloadTask, generation: number, message: string): void {
    if (!this.isCurrent(task, generation)) return;
    this.closeFile(task);
    task.request = undefined;
    task.state = 'failed';
    task.error = message;
    task.updatedAt = Date.now();
    this.emit('state', task);
  }

  private isCurrent(task: NativeDownloadTask, generation: number): boolean {
    return task.generation === generation && task.state === 'running';
  }

  private closeTransport(task: NativeDownloadTask): void {
    const request = task.request;
    task.request = undefined;
    task.pendingResponseData = [];
    task.pendingResponseBytes = 0;
    this.closeFile(task);
    if (request !== undefined) {
      try {
        request.off('dataReceive');
        request.destroy();
      } catch (_error) {
      }
    }
  }

  private closeFile(task: NativeDownloadTask): void {
    const file = task.file;
    task.file = undefined;
    if (file !== undefined) {
      try {
        fs.fsyncSync(file.fd);
      } catch (_error) {
      }
      try {
        fs.closeSync(file);
      } catch (_error) {
      }
    }
  }

  private emit(type: string, task: NativeDownloadTask): void {
    this.persistTaskQuietly(task);
    const payload: NativeDownloadEventPayload = new NativeDownloadEventPayload(type, task);
    for (const context of this.contexts) {
      try {
        context.sendGlobalEvent(DownloadManagerModule.EVENT_NAME, [payload]);
      } catch (_error) {
        // A dead context cannot unregister before this broadcast; drop it.
        this.contexts.delete(context);
      }
    }
  }

  private contentLength(headers: Record<string, string>): number | null {
    const header: string | null = this.headerValue(headers, 'content-length');
    if (header === null) return null;
    const value: number = Number(header);
    return Number.isSafeInteger(value) && value >= 0 ? value : null;
  }

  private addContentLength(length: number | null, offset: number): number | null {
    if (length === null) return null;
    const total: number = length + offset;
    if (!this.isSafeInteger(total)) {
      throw new Error('Invalid or unsupported Content-Length');
    }
    return total;
  }

  private headerValue(headers: Record<string, string>, expectedName: string): string | null {
    for (const name of Object.keys(headers)) {
      if (name.toLowerCase() === expectedName) return headers[name].trim();
    }
    return null;
  }

  private contentRangeStart(value: string | null): number | null {
    if (value === null) return null;
    const normalized: string = value.trim();
    if (!normalized.toLowerCase().startsWith('bytes ')) return null;
    const dash: number = normalized.indexOf('-', 6);
    const slash: number = normalized.lastIndexOf('/');
    if (dash < 0 || slash < dash) return null;
    const start: number = Number(normalized.substring(6, dash).trim());
    return this.isSafeInteger(start) ? start : null;
  }

  private contentRangeTotal(value: string | null): number | null {
    if (value === null) return null;
    const slash: number = value.lastIndexOf('/');
    if (slash < 0 || slash === value.length - 1) return null;
    const text: string = value.substring(slash + 1).trim();
    if (text === '*') return null;
    const total: number = Number(text);
    return this.isSafeInteger(total) ? total : null;
  }

  private unsatisfiedRangeTotal(value: string | null): number | null {
    if (value === null || !value.trim().toLowerCase().startsWith('bytes */')) return null;
    return this.contentRangeTotal(value);
  }

  private responseValidator(headers: Record<string, string>): string | null {
    const etag: string | null = this.headerValue(headers, 'etag');
    if (etag !== null && etag.length > 0 && !etag.startsWith('W/')) return etag;
    const lastModified: string | null = this.headerValue(headers, 'last-modified');
    return lastModified !== null && lastModified.length > 0 ? lastModified : null;
  }

  private loadPersistedTasksOnce(): void {
    if (this.persistedTasksLoaded) return;
    this.persistedTasksLoaded = true;
    const directory: string = this.metadataDirectory();
    if (!fs.accessSync(directory)) return;
    const names: Array<string> = fs.listFileSync(directory);
    for (const name of names) {
      if (!name.endsWith('.json')) continue;
      const path: string = `${directory}/${name}`;
      try {
        if (fs.statSync(path).size > NativeDownloadStore.MAX_METADATA_BYTES) {
          throw new Error('Persisted task metadata is too large');
        }
        const value = JSON.parse(fs.readTextSync(path)) as PersistedDownloadTaskValue;
        const task: NativeDownloadTask = this.restoreTask(value);
        if (name !== `${task.id}.json` || this.tasks.has(task.id)) {
          throw new Error('Persisted task file name does not match its ID');
        }
        this.tasks.set(task.id, task);
        this.persistTaskQuietly(task);
      } catch (_error) {
        this.deleteIfExists(path);
      }
    }
  }

  private restoreTask(value: PersistedDownloadTaskValue): NativeDownloadTask {
    if (value.version !== 1 || value.persistProgress !== true ||
      typeof value.id !== 'string' || typeof value.url !== 'string' ||
      typeof value.fileName !== 'string' || typeof value.progressIntervalMs !== 'number' ||
      typeof value.state !== 'string' || typeof value.createdAt !== 'number' ||
      typeof value.updatedAt !== 'number' || typeof value.bytesDownloaded !== 'number' ||
      (value.totalBytes !== null && typeof value.totalBytes !== 'number') ||
      (value.error !== null && typeof value.error !== 'string') ||
      (value.rangeValidator !== null && typeof value.rangeValidator !== 'string')) {
      throw new Error('Invalid persisted download task');
    }
    if (!this.isKnownState(value.state) || !this.isSafeInteger(value.createdAt) ||
      !this.isSafeInteger(value.updatedAt) || !this.isSafeInteger(value.bytesDownloaded) ||
      (value.totalBytes !== null && !this.isSafeInteger(value.totalBytes))) {
      throw new Error('Invalid persisted download task state');
    }
    const options = new RestoredDownloadOptions(value);
    const validationError: string = this.validateOptions(options);
    if (validationError.length > 0) throw new Error(validationError);

    const task = new NativeDownloadTask(options, value.createdAt);
    task.state = value.state;
    task.totalBytes = value.totalBytes;
    task.rangeValidator = value.rangeValidator;
    if (task.rangeValidator !== null && (task.rangeValidator.length === 0 ||
      task.rangeValidator.length > 8192 || task.rangeValidator.includes('\r') ||
      task.rangeValidator.includes('\n'))) {
      throw new Error('Invalid persisted range validator');
    }
    task.error = value.error === null
      ? null
      : value.error.substring(0, Math.min(4096, value.error.length));
    task.updatedAt = Math.max(value.createdAt, value.updatedAt);
    const partial: string = this.partialPath(task);
    const destination: string = this.destinationPath(task);
    if (task.state === 'completed') {
      if (fs.accessSync(destination)) {
        const size: number = fs.statSync(destination).size;
        if (!this.isSafeInteger(size)) throw new Error('Downloaded file is too large');
        task.bytesDownloaded = size;
        task.totalBytes = size;
        task.fileUri = fileUri.getUriFromPath(destination);
        task.error = null;
      } else {
        task.state = 'failed';
        task.bytesDownloaded = this.fileSize(partial);
        task.totalBytes = null;
        task.fileUri = null;
        task.error = 'Downloaded file is missing';
        task.updatedAt = Date.now();
      }
    } else if (task.state === 'cancelled') {
      this.deleteIfExists(partial);
      task.bytesDownloaded = 0;
      task.fileUri = null;
    } else {
      task.bytesDownloaded = this.fileSize(partial);
      task.fileUri = null;
      if (task.state === 'queued' || task.state === 'running') {
        task.state = 'paused';
        task.error = null;
        task.updatedAt = Date.now();
      }
    }
    if (task.totalBytes !== null && task.totalBytes < task.bytesDownloaded) {
      task.totalBytes = null;
    }
    return task;
  }

  private persistTask(task: NativeDownloadTask): void {
    if (!task.persistProgress) return;
    const directory: string = this.metadataDirectory();
    if (!fs.accessSync(directory)) fs.mkdirSync(directory, true);
    const destination: string = this.metadataPath(task);
    const temporary: string = `${destination}.tmp`;
    const file: fs.File = fs.openSync(
      temporary,
      fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC,
    );
    try {
      fs.writeSync(file.fd, JSON.stringify(new PersistedDownloadTaskValue(task)));
      fs.fsyncSync(file.fd);
    } finally {
      fs.closeSync(file);
    }
    fs.moveFileSync(temporary, destination, 0);
  }

  private persistTaskQuietly(task: NativeDownloadTask): void {
    try {
      this.persistTask(task);
    } catch (_error) {
      // A later state or progress event retries the atomic metadata write.
    }
  }

  private deletePersistedTask(task: NativeDownloadTask): void {
    if (!task.persistProgress) return;
    this.deleteIfExists(this.metadataPath(task));
  }

  private deletePersistedTaskQuietly(task: NativeDownloadTask): void {
    try {
      this.deletePersistedTask(task);
    } catch (_error) {
    }
  }

  private metadataDirectory(): string {
    const context = this.abilityContext;
    if (context === undefined) {
      throw new Error('DownloadManager store has no ability context');
    }
    return `${context.filesDir}/LynxFiles/download-manager/tasks`;
  }

  private metadataPath(task: NativeDownloadTask): string {
    return `${this.metadataDirectory()}/${task.id}.json`;
  }

  private fileSize(path: string): number {
    if (!fs.accessSync(path)) return 0;
    const size: number = fs.statSync(path).size;
    if (!this.isSafeInteger(size)) throw new Error('Partial download is too large');
    return size;
  }

  private isKnownState(state: string): boolean {
    return ['queued', 'running', 'paused', 'completed', 'failed', 'cancelled'].includes(state);
  }

  private isSafeInteger(value: number): boolean {
    return Number.isSafeInteger(value) && value >= 0;
  }

  private ensureDirectory(): void {
    const directory: string = this.downloadsDirectory();
    if (!fs.accessSync(directory)) fs.mkdirSync(directory, true);
  }

  private downloadsDirectory(): string {
    const context = this.abilityContext;
    if (context === undefined) {
      throw new Error('DownloadManager store has no ability context');
    }
    return `${context.cacheDir}/LynxFiles/downloads`;
  }

  private destinationPath(task: NativeDownloadTask): string {
    return `${this.downloadsDirectory()}/${task.id}-${task.fileName}`;
  }

  private partialPath(task: NativeDownloadTask): string {
    return `${this.destinationPath(task)}.part`;
  }

  private deleteIfExists(path: string): void {
    if (fs.accessSync(path)) fs.unlinkSync(path);
  }

  private validateOptions(options: NativeDownloadOptions): string {
    if (!new RegExp('^[A-Za-z0-9._-]{1,128}$').test(options.id)) {
      return 'Invalid download task ID';
    }
    const allowedURL: boolean = new RegExp('^https://[^\\s]+$', 'i').test(options.url) ||
      (BuildProfile.DEBUG && new RegExp('^http://[^\\s]+$', 'i').test(options.url));
    if (!allowedURL || options.url.length > 8192) {
      return 'Download URL must use HTTPS (HTTP is Debug-only)';
    }
    if (options.fileName.length < 1 || options.fileName.length > 128 ||
      options.fileName.trim() !== options.fileName || options.fileName === '.' ||
      options.fileName === '..' || new RegExp('[\\\\/\\u0000-\\u001f\\u007f]').test(options.fileName)) {
      return 'Invalid download fileName';
    }
    if (!Number.isInteger(options.progressIntervalMs) ||
      options.progressIntervalMs < 100 || options.progressIntervalMs > 10000) {
      return 'progressIntervalMs must be between 100 and 10000';
    }
    if (typeof options.persistProgress !== 'boolean') {
      return 'persistProgress must be a boolean';
    }
    const names: Array<string> = Object.keys(options.headers);
    if (names.length > 64) return 'Too many download headers';
    const reserved: Array<string> = [
      'accept-encoding', 'connection', 'content-length', 'host', 'if-range', 'range',
      'transfer-encoding',
    ];
    for (const name of names) {
      const value: string = options.headers[name];
      if (!new RegExp("^[!#$%&'*+.^_`|~0-9A-Za-z-]+$").test(name) ||
        reserved.includes(name.toLowerCase()) || value.length > 8192 ||
        value.includes('\r') || value.includes('\n')) {
        return `Invalid download header: ${name}`;
      }
    }
    return '';
  }

  private result(value: Object | null, error: string = ''): string {
    return JSON.stringify(new NativeDownloadResult(value, error));
  }

  private messageOf(error: Object, fallback: string): string {
    return error instanceof Error && error.message.length > 0 ? error.message : fallback;
  }
}

class DownloadManagerLifecycleClient extends LynxViewClient {
  private readonly store: NativeDownloadStore;
  private readonly context: LynxContext;

  constructor(store: NativeDownloadStore, context: LynxContext) {
    super();
    this.store = store;
    this.context = context;
  }

  override onDestroy(): void {
    this.store.detach(this.context);
  }
}

/** Download task manager exported to Lynx as DownloadManager. */
export class DownloadManagerModule extends LynxModule {
  static readonly NAME: string = 'DownloadManager';
  static readonly EVENT_NAME: string = 'downloadManager';
  private readonly store: NativeDownloadStore;

  constructor(context: LynxContext, param?: Object) {
    super(context, param);
    this.store = NativeDownloadStore.shared(
      getContext(this) as common.UIAbilityContext,
    );
    this.store.attach(context);
    context.getLynxViewClient()?.push(new DownloadManagerLifecycleClient(this.store, context));
  }

  getCapabilities(callback: (resultJSON: string) => void): void {
    this.store.capabilities(callback);
  }

  enqueue(options: NativeDownloadOptions, callback: (resultJSON: string) => void): void {
    this.store.enqueue(options, callback);
  }

  pause(id: string, callback: (resultJSON: string) => void): void {
    this.store.pause(id, callback);
  }

  resume(id: string, callback: (resultJSON: string) => void): void {
    this.store.resume(id, callback);
  }

  cancel(id: string, callback: (resultJSON: string) => void): void {
    this.store.cancel(id, callback);
  }

  remove(id: string, deleteFile: boolean, callback: (resultJSON: string) => void): void {
    this.store.remove(id, deleteFile, callback);
  }

  getTask(id: string, callback: (resultJSON: string) => void): void {
    this.store.getTask(id, callback);
  }

  listTasks(callback: (resultJSON: string) => void): void {
    this.store.listTasks(callback);
  }
}
