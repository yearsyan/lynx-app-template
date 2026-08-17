/** Metadata resolved from a picker URI by the platform file system. */
export interface FileInfo {
  uri: string;
  name: string;
  mimeType: string | null;
  size: number | null;
}

export interface ReadFileOptions {
  /** Maximum source bytes accepted by the bridge. */
  maxBytes?: number;
}

export interface PickerOptions {
  /** Maximum number of items the user may select. Defaults to 1. */
  maxSelection?: number;
}

/** Native picker surface shared by `FileSystem.pick` and `AlbumUtils.pick`. */
export interface PickerModule {
  pick(maxSelection: number, callback: (resultJSON: string) => void): void;
}

interface FileSystemModule {
  pick(maxSelection: number, callback: (resultJSON: string) => void): void;
  stat(uri: string, callback: (resultJSON: string) => void): void;
  copyToCache(uri: string, callback: (resultJSON: string) => void): void;
  readText(
    uri: string,
    maxBytes: number,
    callback: (resultJSON: string) => void,
  ): void;
  readBase64(
    uri: string,
    maxBytes: number,
    callback: (resultJSON: string) => void,
  ): void;
}

interface AppModules {
  FileSystem?: FileSystemModule;
}

interface FileSystemResult {
  error?: unknown;
  value?: unknown;
}

interface PickerResult {
  error?: unknown;
  uris?: unknown;
}

const DEFAULT_TEXT_MAX_BYTES = 1024 * 1024;
const DEFAULT_BASE64_MAX_BYTES = 5 * 1024 * 1024;
const MAX_READ_BYTES = 20 * 1024 * 1024;
const MAX_PICKER_SELECTION = 50;

function requireFileSystem(): FileSystemModule {
  'background only';
  const module = (NativeModules as AppModules).FileSystem;
  if (module === undefined) {
    throw new Error('FileSystem is not registered by the host');
  }
  return module;
}

function normalizeURI(uri: string): string {
  'background only';
  const normalized = uri.trim();
  if (normalized.length === 0) {
    throw new Error('File URI must not be empty');
  }
  return normalized;
}

function normalizeMaxBytes(
  options: ReadFileOptions,
  defaultValue: number,
): number {
  'background only';
  const value = options.maxBytes ?? defaultValue;
  if (!Number.isInteger(value) || value < 1 || value > MAX_READ_BYTES) {
    throw new Error(
      `File maxBytes must be an integer from 1 to ${MAX_READ_BYTES}`,
    );
  }
  return value;
}

export function normalizePickerOptions(options: PickerOptions): number {
  'background only';
  const maxSelection = options.maxSelection ?? 1;
  if (
    !Number.isInteger(maxSelection) ||
    maxSelection < 1 ||
    maxSelection > MAX_PICKER_SELECTION
  ) {
    throw new Error(
      `Picker maxSelection must be an integer from 1 to ${MAX_PICKER_SELECTION}`,
    );
  }
  return maxSelection;
}

export function completePicker(
  module: PickerModule,
  maxSelection: number,
): Promise<string[]> {
  'background only';
  return new Promise((resolve, reject) => {
    module.pick(maxSelection, (resultJSON) => {
      'background only';
      try {
        if (typeof resultJSON !== 'string') {
          throw new Error('Native picker returned a non-string result');
        }
        const result = JSON.parse(resultJSON) as unknown;
        if (typeof result !== 'object' || result === null) {
          throw new Error('Native picker returned an invalid result');
        }
        const payload = result as PickerResult;
        if (typeof payload.error === 'string' && payload.error.length > 0) {
          reject(new Error(payload.error));
          return;
        }
        if (
          !Array.isArray(payload.uris) ||
          !payload.uris.every((uri) => typeof uri === 'string')
        ) {
          throw new Error('Native picker returned an invalid URI list');
        }
        resolve(payload.uris.slice(0, maxSelection));
      } catch (error) {
        reject(
          error instanceof Error
            ? error
            : new Error('Unable to decode the native picker result'),
        );
      }
    });
  });
}

function invoke<T>(
  action: (callback: (resultJSON: string) => void) => void,
  decode: (value: unknown) => T,
): Promise<T> {
  'background only';
  return new Promise((resolve, reject) => {
    try {
      action((resultJSON) => {
        'background only';
        try {
          if (typeof resultJSON !== 'string') {
            throw new Error('FileSystem returned a non-string result');
          }
          const parsed = JSON.parse(resultJSON) as unknown;
          if (typeof parsed !== 'object' || parsed === null) {
            throw new Error('FileSystem returned an invalid result');
          }
          const result = parsed as FileSystemResult;
          if (typeof result.error === 'string' && result.error.length > 0) {
            reject(new Error(result.error));
            return;
          }
          resolve(decode(result.value));
        } catch (error) {
          reject(error instanceof Error ? error : new Error(String(error)));
        }
      });
    } catch (error) {
      reject(error instanceof Error ? error : new Error(String(error)));
    }
  });
}

function decodeString(value: unknown): string {
  'background only';
  if (typeof value !== 'string') {
    throw new Error('FileSystem returned an invalid string');
  }
  return value;
}

function decodeFileInfo(value: unknown): FileInfo {
  'background only';
  if (typeof value !== 'object' || value === null) {
    throw new Error('FileSystem returned invalid file metadata');
  }
  const info = value as Partial<FileInfo>;
  if (
    typeof info.uri !== 'string' ||
    typeof info.name !== 'string' ||
    (info.mimeType !== null && typeof info.mimeType !== 'string') ||
    (info.size !== null &&
      (typeof info.size !== 'number' ||
        !Number.isSafeInteger(info.size) ||
        info.size < 0))
  ) {
    throw new Error('FileSystem returned invalid file metadata');
  }
  return info as FileInfo;
}

function base64CharValue(char: string): number {
  'background only';
  const code = char.charCodeAt(0);
  if (code >= 65 && code <= 90) {
    return code - 65;
  }
  if (code >= 97 && code <= 122) {
    return code - 97 + 26;
  }
  if (code >= 48 && code <= 57) {
    return code - 48 + 52;
  }
  if (char === '+') {
    return 62;
  }
  if (char === '/') {
    return 63;
  }
  return -1;
}

function decodeBase64(value: string): ArrayBuffer {
  'background only';
  let length = value.length;
  while (length > 0 && value.charCodeAt(length - 1) === 61) {
    length -= 1;
  }
  const remainder = length % 4;
  if (remainder === 1) {
    throw new Error('FileSystem returned truncated Base64');
  }
  const byteLength =
    Math.floor(length / 4) * 3 +
    (remainder === 2 ? 1 : remainder === 3 ? 2 : 0);
  const bytes = new Uint8Array(byteLength);
  let offset = 0;
  let buffer = 0;
  let bits = 0;
  for (let index = 0; index < length; index++) {
    const charValue = base64CharValue(value.charAt(index));
    if (charValue < 0) {
      throw new Error('FileSystem returned invalid Base64');
    }
    buffer = (buffer << 6) | charValue;
    bits += 6;
    if (bits >= 8) {
      bits -= 8;
      bytes[offset] = (buffer >> bits) & 0xff;
      offset += 1;
    }
  }
  return bytes.buffer as ArrayBuffer;
}

function decodeArrayBuffer(value: unknown): ArrayBuffer {
  'background only';
  if (typeof value !== 'string') {
    throw new Error('FileSystem returned an invalid string');
  }
  return decodeBase64(value);
}

/** URI-aware file access shared by Android, iOS and HarmonyOS hosts. */
export const fileSystem = {
  /** Selects arbitrary files through the platform's user-visible system picker. */
  pick(options: PickerOptions = {}): Promise<string[]> {
    'background only';
    const maxSelection = normalizePickerOptions(options);
    return completePicker(requireFileSystem(), maxSelection);
  },

  stat(uri: string): Promise<FileInfo> {
    'background only';
    const normalized = normalizeURI(uri);
    return invoke(
      (callback) => requireFileSystem().stat(normalized, callback),
      decodeFileInfo,
    );
  },

  /** Copies a picker URI into app cache and returns a cache file URI. */
  copyToCache(uri: string): Promise<string> {
    'background only';
    const normalized = normalizeURI(uri);
    return invoke(
      (callback) => requireFileSystem().copyToCache(normalized, callback),
      decodeString,
    );
  },

  /** Reads a UTF-8 file. Defaults to a 1 MiB source limit. */
  readText(uri: string, options: ReadFileOptions = {}): Promise<string> {
    'background only';
    const normalized = normalizeURI(uri);
    const maxBytes = normalizeMaxBytes(options, DEFAULT_TEXT_MAX_BYTES);
    return invoke(
      (callback) =>
        requireFileSystem().readText(normalized, maxBytes, callback),
      decodeString,
    );
  },

  /** Reads bytes as standard Base64. Defaults to a 5 MiB source limit. */
  readBase64(uri: string, options: ReadFileOptions = {}): Promise<string> {
    'background only';
    const normalized = normalizeURI(uri);
    const maxBytes = normalizeMaxBytes(options, DEFAULT_BASE64_MAX_BYTES);
    return invoke(
      (callback) =>
        requireFileSystem().readBase64(normalized, maxBytes, callback),
      decodeString,
    );
  },

  /**
   * Reads bytes into an ArrayBuffer. Decodes the Base64 bridge payload in
   * JavaScript, so the same `maxBytes` source limit and inflation overhead
   * as `readBase64` apply. Defaults to a 5 MiB source limit.
   */
  readArrayBuffer(
    uri: string,
    options: ReadFileOptions = {},
  ): Promise<ArrayBuffer> {
    'background only';
    const normalized = normalizeURI(uri);
    const maxBytes = normalizeMaxBytes(options, DEFAULT_BASE64_MAX_BYTES);
    return invoke(
      (callback) =>
        requireFileSystem().readBase64(normalized, maxBytes, callback),
      decodeArrayBuffer,
    );
  },
};
