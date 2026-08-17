/**
 * Raw Clipboard NativeModule transport contract.
 *
 * The native API intentionally keeps callbacks; high-level Promise and
 * runtime validation live in @lynx-app/native-bridge.
 *
 * @lynxmodule
 */
export declare class Clipboard {
  setString(text: string, callback: (error: string) => void): void;
  getString(callback: (text: string | null) => void): void;
}
