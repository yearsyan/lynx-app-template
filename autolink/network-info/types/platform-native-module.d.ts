/**
 * Raw NetworkInfo NativeModule transport contract.
 *
 * The native API intentionally keeps callbacks; this package's src/index.ts
 * owns the high-level Promise API and runtime validation.
 *
 * @lynxmodule
 */
export declare class NetworkInfo {
  getInfo(callback: (resultJSON: string) => void): void;
  start(callback: (error: string) => void): void;
  stop(callback: (error: string) => void): void;
}
