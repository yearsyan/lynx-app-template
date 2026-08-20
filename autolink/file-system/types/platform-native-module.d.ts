/**
 * Raw FileSystem NativeModule transport contract.
 *
 * The native API intentionally keeps callbacks; high-level Promise and
 * runtime validation live in @lynx-app/native-bridge.
 *
 * @lynxmodule
 */
export declare class FileSystem {
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
  writeText(
    uri: string,
    contents: string,
    append: boolean,
    callback: (resultJSON: string) => void,
  ): void;
  writeBase64(
    uri: string,
    base64: string,
    append: boolean,
    callback: (resultJSON: string) => void,
  ): void;
  delete(uri: string, callback: (resultJSON: string) => void): void;
  listDir(uri: string, callback: (resultJSON: string) => void): void;
  cacheDir(callback: (resultJSON: string) => void): void;
}
