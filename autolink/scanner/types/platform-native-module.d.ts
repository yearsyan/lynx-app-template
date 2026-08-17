/**
 * Raw Scanner NativeModule transport contract.
 *
 * The native API intentionally keeps callbacks; high-level Promise and
 * runtime validation live in @lynx-app/native-bridge.
 *
 * @lynxmodule
 */
export declare class Scanner {
  scan(callback: (resultJSON: string) => void): void;
  scanFromImage(uri: string, callback: (resultJSON: string) => void): void;
}
