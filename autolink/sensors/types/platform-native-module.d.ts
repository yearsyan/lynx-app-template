/**
 * Raw Sensors NativeModule transport contract.
 *
 * The native API intentionally keeps callbacks; high-level Promise and
 * runtime validation live in @lynx-app/native-bridge.
 *
 * @lynxmodule
 */
export declare class Sensors {
  isAvailable(type: string, callback: (resultJSON: string) => void): void;
  start(type: string, callback: (error: string) => void): void;
  stop(type: string, callback: (error: string) => void): void;
}
