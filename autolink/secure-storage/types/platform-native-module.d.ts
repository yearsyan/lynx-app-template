/**
 * Raw SecureStorage NativeModule transport contract.
 *
 * The native API intentionally keeps callbacks; high-level Promise and
 * runtime validation live in @lynx-app/native-bridge.
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
