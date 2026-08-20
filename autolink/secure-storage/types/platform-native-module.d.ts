/**
 * Raw SecureStorage NativeModule transport contract.
 *
 * The native API intentionally keeps callbacks; this package's src/index.ts
 * owns the high-level Promise API and runtime validation.
 *
 * @lynxmodule
 */
export declare class SecureStorage {
  setString(
    key: string,
    value: string,
    callback: (error: string) => void,
  ): void;
  getString(
    key: string,
    defaultValue: string | null,
    callback: (value: string | null) => void,
  ): void;
  remove(key: string, callback: (error: string) => void): void;
}
