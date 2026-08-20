import {
  decodeNativeEnvelope,
  decodeNativeValue,
  requireNativeModule,
} from './bridge.generated.js';
import type { FileSystemModule } from './native.generated.js';

export * from './native.generated.js';

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

export interface WriteFileOptions {
  /** Appends to an existing file instead of truncating it. */
  append?: boolean;
}

/** Directory entry resolved from the cache sandbox by `listDir`. */
export interface CacheEntry {
  name: string;
  uri: string;
  isDirectory: boolean;
  size: number | null;
}

export interface PickerOptions {
  /** Maximum number of items the user may select. Defaults to 1. */
  maxSelection?: number;
}

/** Native picker surface shared by `FileSystem.pick` and `AlbumUtils.pick`. */
export type PickerModule = Pick<FileSystemModule, 'pick'>;

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
const MAX_WRITE_BYTES = 20 * 1024 * 1024;
const MAX_PICKER_SELECTION = 50;

function requireFileSystem(): FileSystemModule {
  'background only';
  return requireNativeModule();
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

function normalizeWriteOptions(options: WriteFileOptions): boolean {
  'background only';
  const append = options.append ?? false;
  if (typeof append !== 'boolean') {
    throw new Error('File append must be a boolean');
  }
  return append;
}

export function completePicker(
  module: PickerModule,
  maxSelection: number,
): Promise<string[]> {
  'background only';
  return new Promise((resolve, reject) => {
    module.pick(maxSelection, (resultValue) => {
      'background only';
      try {
        const result = decodeNativeValue(resultValue, 'Native picker');
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
  action: (callback: (result: unknown) => void) => void,
  decode: (value: unknown) => T,
): Promise<T> {
  'background only';
  return new Promise((resolve, reject) => {
    try {
      action((resultValue) => {
        'background only';
        try {
          const result = decodeNativeEnvelope(
            resultValue,
            'FileSystem',
          ) as FileSystemResult;
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

const BASE64_ALPHABET =
  'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
const BASE64_CHUNK_TRIPLETS = 5460;

function encodeBase64(bytes: Uint8Array): string {
  'background only';
  const chunkBytes = BASE64_CHUNK_TRIPLETS * 3;
  const chunks: string[] = [];
  for (let offset = 0; offset < bytes.length; offset += chunkBytes) {
    const limit = Math.min(offset + chunkBytes, bytes.length);
    let chunk = '';
    let index = offset;
    for (; index + 3 <= limit; index += 3) {
      const byte0 = bytes[index];
      const byte1 = bytes[index + 1];
      const byte2 = bytes[index + 2];
      if (byte0 === undefined || byte1 === undefined || byte2 === undefined) {
        break;
      }
      const triplet = (byte0 << 16) | (byte1 << 8) | byte2;
      chunk +=
        BASE64_ALPHABET.charAt((triplet >> 18) & 0x3f) +
        BASE64_ALPHABET.charAt((triplet >> 12) & 0x3f) +
        BASE64_ALPHABET.charAt((triplet >> 6) & 0x3f) +
        BASE64_ALPHABET.charAt(triplet & 0x3f);
    }
    const remainderByte0 = bytes[index];
    const remainderByte1 = bytes[index + 1];
    if (index < limit && remainderByte0 !== undefined) {
      if (remainderByte1 === undefined) {
        chunk +=
          BASE64_ALPHABET.charAt(remainderByte0 >> 2) +
          BASE64_ALPHABET.charAt((remainderByte0 & 0x3) << 4) +
          '==';
      } else {
        const pair = (remainderByte0 << 8) | remainderByte1;
        chunk +=
          BASE64_ALPHABET.charAt(pair >> 10) +
          BASE64_ALPHABET.charAt((pair >> 4) & 0x3f) +
          BASE64_ALPHABET.charAt((pair & 0xf) << 2) +
          '=';
      }
    }
    chunks.push(chunk);
  }
  return chunks.join('');
}

function validateBase64(value: string): void {
  'background only';
  let length = value.length;
  while (length > 0 && value.charCodeAt(length - 1) === 61) {
    length -= 1;
  }
  if (length % 4 === 1) {
    throw new Error('File contents are truncated Base64');
  }
  for (let index = 0; index < length; index += 1) {
    if (base64CharValue(value.charAt(index)) < 0) {
      throw new Error('File contents are invalid Base64');
    }
  }
}

function decodeVoid(): undefined {
  'background only';
  return undefined;
}

function decodeCacheEntry(value: unknown): CacheEntry {
  'background only';
  if (typeof value !== 'object' || value === null) {
    throw new Error('FileSystem returned an invalid directory entry');
  }
  const entry = value as Partial<CacheEntry>;
  if (
    typeof entry.name !== 'string' ||
    typeof entry.uri !== 'string' ||
    typeof entry.isDirectory !== 'boolean' ||
    (entry.size !== null &&
      (typeof entry.size !== 'number' ||
        !Number.isSafeInteger(entry.size) ||
        entry.size < 0))
  ) {
    throw new Error('FileSystem returned an invalid directory entry');
  }
  return entry as CacheEntry;
}

function decodeCacheEntries(value: unknown): CacheEntry[] {
  'background only';
  if (!Array.isArray(value)) {
    throw new Error('FileSystem returned an invalid directory listing');
  }
  return value.map((entry) => decodeCacheEntry(entry));
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

  /** Writes UTF-8 text into the cache sandbox and returns the file URI. */
  writeText(
    uri: string,
    contents: string,
    options: WriteFileOptions = {},
  ): Promise<string> {
    'background only';
    const normalized = normalizeURI(uri);
    if (contents.length > MAX_WRITE_BYTES) {
      throw new Error(`File contents must not exceed ${MAX_WRITE_BYTES} bytes`);
    }
    const append = normalizeWriteOptions(options);
    return invoke(
      (callback) =>
        requireFileSystem().writeText(normalized, contents, append, callback),
      decodeString,
    );
  },

  /**
   * Writes Base64-decoded bytes into the cache sandbox and returns the file
   * URI. Accepts standard Base64 with optional trailing padding.
   */
  writeBase64(
    uri: string,
    base64: string,
    options: WriteFileOptions = {},
  ): Promise<string> {
    'background only';
    const normalized = normalizeURI(uri);
    validateBase64(base64);
    const append = normalizeWriteOptions(options);
    return invoke(
      (callback) =>
        requireFileSystem().writeBase64(normalized, base64, append, callback),
      decodeString,
    );
  },

  /**
   * Writes binary data into the cache sandbox. Encodes to Base64 in
   * JavaScript before crossing the bridge, so the same `MAX_WRITE_BYTES`
   * limit and inflation overhead as `writeBase64` apply.
   */
  writeArrayBuffer(
    uri: string,
    data: ArrayBuffer | Uint8Array,
    options: WriteFileOptions = {},
  ): Promise<string> {
    'background only';
    const normalized = normalizeURI(uri);
    const bytes = data instanceof Uint8Array ? data : new Uint8Array(data);
    if (bytes.byteLength > MAX_WRITE_BYTES) {
      throw new Error(`File contents must not exceed ${MAX_WRITE_BYTES} bytes`);
    }
    const append = normalizeWriteOptions(options);
    const encoded = encodeBase64(bytes);
    return invoke(
      (callback) =>
        requireFileSystem().writeBase64(normalized, encoded, append, callback),
      decodeString,
    );
  },

  /**
   * Deletes a file or directory (recursively) inside the cache sandbox.
   * Deleting the sandbox root itself clears the whole cache.
   */
  delete(uri: string): Promise<void> {
    'background only';
    const normalized = normalizeURI(uri);
    return invoke(
      (callback) => requireFileSystem().delete(normalized, callback),
      decodeVoid,
    );
  },

  /** Lists a sandbox directory's entries, sorted by name. */
  listDir(uri: string): Promise<CacheEntry[]> {
    'background only';
    const normalized = normalizeURI(uri);
    return invoke(
      (callback) => requireFileSystem().listDir(normalized, callback),
      decodeCacheEntries,
    );
  },

  /** Returns the cache sandbox root directory as a `file://` URI. */
  cacheDir(): Promise<string> {
    'background only';
    return invoke(
      (callback) => requireFileSystem().cacheDir(callback),
      decodeString,
    );
  },
};
