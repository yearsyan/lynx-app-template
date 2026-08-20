/**
 * Raw Scanner NativeModule transport contract.
 *
 * The native API intentionally keeps callbacks; this package's src/index.ts
 * owns the high-level Promise API and runtime validation.
 *
 * @lynxmodule
 */
export declare class Scanner {
  scan(callback: (resultJSON: string) => void): void;
  scanFromImage(uri: string, callback: (resultJSON: string) => void): void;
}
