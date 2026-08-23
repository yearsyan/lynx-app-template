/**
 * Raw Storage NativeModule transport contract: the shared MMKV-backed KV
 * store plus the small-secret secure store in one module. The secure
 * methods are prefixed with `secure` because both stores expose the same
 * string primitive shapes.
 *
 * The native API intentionally keeps callbacks; this package's src/index.ts
 * owns the high-level Promise API and runtime validation.
 *
 * @lynxmodule
 */
export declare class Storage {
  /**
   * `inMemory` writes only the process-wide overlay dictionary (the MMKV
   * copy is left untouched); a persisted write clears the overlay entry for
   * the key first. Reads always check the overlay before MMKV.
   */
  setString(
    key: string,
    value: string,
    callback: (error: string) => void,
    inMemory: boolean,
  ): void;
  getString(
    key: string,
    defaultValue: string,
    callback: (value: string | null) => void,
  ): void;
  getStringOrNull(key: string, callback: (value: string | null) => void): void;
  remove(key: string, callback: (error: string) => void): void;
  clear(callback: (error: string) => void): void;
  contains(key: string, callback: (contains: boolean) => void): void;
  secureSetString(
    key: string,
    value: string,
    callback: (error: string) => void,
  ): void;
  secureGetString(
    key: string,
    defaultValue: string,
    callback: (value: string | null) => void,
  ): void;
  secureGetStringOrNull(
    key: string,
    callback: (value: string | null) => void,
  ): void;
  secureRemove(key: string, callback: (error: string) => void): void;
}
