/**
 * Raw Clipboard NativeModule transport contract.
 *
 * The native API intentionally keeps callbacks; this package's src/index.ts
 * owns the high-level Promise API and runtime validation.
 *
 * @lynxmodule
 */
export declare class Clipboard {
  setString(text: string, callback: (error: string) => void): void;
  getString(callback: (text: string | null) => void): void;
}
