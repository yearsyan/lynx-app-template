import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { LynxContext, LynxModule } from '@lynx/lynx';

class FileInfo {
  uri: string;
  name: string;
  mimeType: string | null;
  size: number;

  constructor(uri: string, name: string, mimeType: string | null, size: number) {
    this.uri = uri;
    this.name = name;
    this.mimeType = mimeType;
    this.size = size;
  }
}

class FileInfoResult {
  value: FileInfo | null;
  error: string;

  constructor(value: FileInfo | null, error: string = '') {
    this.value = value;
    this.error = error;
  }
}

class FileStringResult {
  value: string;
  error: string;

  constructor(value: string = '', error: string = '') {
    this.value = value;
    this.error = error;
  }
}

class PickerResult {
  uris: Array<string>;
  error: string;

  constructor(uris: Array<string> = [], error: string = '') {
    this.uris = uris;
    this.error = error;
  }
}

export class FileSystemRegistration {
  readonly context: common.UIAbilityContext;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }
}

/** System file picker and URI-aware file operations exported to Lynx as FileSystem. */
export class FileSystemModule extends LynxModule {
  static readonly NAME: string = 'FileSystem';
  private static readonly MAX_READ_BYTES: number = 20 * 1024 * 1024;
  private static nextCacheID: number = 0;

  private readonly registration: FileSystemRegistration | undefined;
  private readonly base64: util.Base64Helper = new util.Base64Helper();
  private isPicking: boolean = false;

  constructor(context: LynxContext, param?: Object) {
    super(context, param);
    this.registration = param as FileSystemRegistration | undefined;
  }

  pick(maxSelection: number, callback: (resultJSON: string) => void): void {
    if (!Number.isInteger(maxSelection) || maxSelection < 1 || maxSelection > 50) {
      callback(this.pickerError('File picker maxSelection must be between 1 and 50'));
      return;
    }
    if (this.registration === undefined) {
      callback(this.pickerError('File picker has no UIAbilityContext'));
      return;
    }
    if (this.isPicking) {
      callback(this.pickerError('Another file picker request is already active'));
      return;
    }
    this.isPicking = true;

    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = maxSelection;
    try {
      const documentPicker = new picker.DocumentViewPicker(this.registration.context);
      documentPicker.select(options).then((uris: Array<string>) => {
        this.isPicking = false;
        callback(this.pickerURIs(uris.slice(0, maxSelection)));
      }).catch((error: Error) => {
        this.isPicking = false;
        if (this.isCancellation(error)) {
          callback(this.pickerURIs([]));
          return;
        }
        callback(this.pickerError(this.errorMessage(error, 'Unable to select files')));
      });
    } catch (error) {
      this.isPicking = false;
      const pickerError = error as Error;
      callback(this.pickerError(this.errorMessage(pickerError, 'Unable to open the file picker')));
    }
  }

  stat(uri: string, callback: (resultJSON: string) => void): void {
    try {
      const file: fs.File = this.openFile(uri);
      let size: number = 0;
      try {
        size = fs.statSync(file.fd).size;
      } finally {
        fs.closeSync(file);
      }
      const name: string = this.fileName(uri);
      callback(JSON.stringify(new FileInfoResult(
        new FileInfo(uri, name, this.mimeType(name), size),
      )));
    } catch (error) {
      callback(JSON.stringify(new FileInfoResult(null, this.errorMessage(error))));
    }
  }

  copyToCache(uri: string, callback: (resultJSON: string) => void): void {
    if (this.registration === undefined) {
      callback(this.stringError('FileSystem has no UIAbilityContext'));
      return;
    }
    let source: fs.File | undefined;
    try {
      const directory: string = `${this.registration.context.cacheDir}/LynxFiles`;
      if (!fs.accessSync(directory)) {
        fs.mkdirSync(directory, true);
      }
      FileSystemModule.nextCacheID += 1;
      const destination: string = `${directory}/${Date.now()}-${FileSystemModule.nextCacheID}-${
        this.sanitizeName(this.fileName(uri))}`;
      source = this.openFile(uri);
      fs.copyFileSync(source.fd, destination);
      callback(JSON.stringify(new FileStringResult(`file://${destination}`)));
    } catch (error) {
      callback(this.stringError(this.errorMessage(error)));
    } finally {
      if (source !== undefined) {
        fs.closeSync(source);
      }
    }
  }

  readText(uri: string, maxBytes: number, callback: (resultJSON: string) => void): void {
    try {
      const bytes: Uint8Array = this.readBytes(uri, maxBytes);
      const decoder: util.TextDecoder = util.TextDecoder.create('utf-8', { fatal: true });
      callback(JSON.stringify(new FileStringResult(decoder.decodeToString(bytes))));
    } catch (error) {
      callback(this.stringError(this.errorMessage(error)));
    }
  }

  readBase64(uri: string, maxBytes: number, callback: (resultJSON: string) => void): void {
    try {
      const bytes: Uint8Array = this.readBytes(uri, maxBytes);
      callback(JSON.stringify(new FileStringResult(this.base64.encodeToStringSync(bytes))));
    } catch (error) {
      callback(this.stringError(this.errorMessage(error)));
    }
  }

  private readBytes(uri: string, maxBytes: number): Uint8Array {
    if (!Number.isInteger(maxBytes) || maxBytes < 1 ||
      maxBytes > FileSystemModule.MAX_READ_BYTES) {
      throw new Error(
        `File maxBytes must be between 1 and ${FileSystemModule.MAX_READ_BYTES}`,
      );
    }
    const file: fs.File = this.openFile(uri);
    try {
      const size: number = fs.statSync(file.fd).size;
      if (size > maxBytes) {
        throw new Error(`File exceeds maxBytes (${maxBytes})`);
      }
      const buffer: ArrayBuffer = new ArrayBuffer(size);
      let offset: number = 0;
      while (offset < size) {
        const count: number = fs.readSync(file.fd, buffer, {
          offset: offset,
          length: size - offset,
        });
        if (count <= 0) {
          break;
        }
        offset += count;
      }
      if (offset !== size) {
        throw new Error('Unable to read the complete file');
      }
      return new Uint8Array(buffer);
    } finally {
      fs.closeSync(file);
    }
  }

  private openFile(uri: string): fs.File {
    const normalized: string = uri.trim();
    if (normalized.length === 0) {
      throw new Error('File URI must not be empty');
    }
    return fs.openSync(normalized, fs.OpenMode.READ_ONLY);
  }

  private fileName(uri: string): string {
    let value: string = uri;
    const queryIndex: number = value.indexOf('?');
    if (queryIndex >= 0) {
      value = value.substring(0, queryIndex);
    }
    const separator: number = value.lastIndexOf('/');
    const encoded: string = separator >= 0 ? value.substring(separator + 1) : value;
    if (encoded.length === 0) {
      return 'file';
    }
    try {
      const decoded: string = decodeURIComponent(encoded);
      return decoded.length === 0 ? 'file' : decoded;
    } catch (error) {
      return encoded;
    }
  }

  private sanitizeName(name: string): string {
    const sanitized: string = name.replace(new RegExp('[\\\\/:*?"<>|\\x00-\\x1F]', 'g'), '_').trim();
    if (sanitized.length === 0) {
      return 'file';
    }
    return sanitized.length > 120
      ? sanitized.substring(sanitized.length - 120)
      : sanitized;
  }

  private mimeType(name: string): string | null {
    const extensionIndex: number = name.lastIndexOf('.');
    const extension: string = extensionIndex < 0
      ? ''
      : name.substring(extensionIndex + 1).toLowerCase();
    switch (extension) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'heic':
        return 'image/heic';
      case 'pdf':
        return 'application/pdf';
      case 'txt':
        return 'text/plain';
      case 'json':
        return 'application/json';
      case 'csv':
        return 'text/csv';
      case 'zip':
        return 'application/zip';
      case 'mp4':
        return 'video/mp4';
      default:
        return null;
    }
  }

  private stringError(message: string): string {
    return JSON.stringify(new FileStringResult('', message));
  }

  private pickerURIs(uris: Array<string>): string {
    return JSON.stringify(new PickerResult(uris));
  }

  private pickerError(message: string): string {
    return JSON.stringify(new PickerResult([], message));
  }

  private isCancellation(error: Error): boolean {
    const message = error.message.toLowerCase();
    return message.includes('cancel') || message.includes('取消');
  }

  private errorMessage(error: Object, fallback: string = ''): string {
    const typed: Error = error as Error;
    if (typed.message !== undefined && typed.message.length > 0) {
      return typed.message;
    }
    return fallback.length > 0 ? fallback : 'FileSystem operation failed';
  }
}
