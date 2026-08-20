/**
 * Raw Sensors NativeModule transport contract.
 *
 * The native API intentionally keeps callbacks; this package's src/index.ts
 * owns the high-level Promise API and runtime validation.
 *
 * @lynxmodule
 */
export declare class Sensors {
  isAvailable(type: string, callback: (resultJSON: string) => void): void;
  start(type: string, callback: (error: string) => void): void;
  stop(type: string, callback: (error: string) => void): void;
}
