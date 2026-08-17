/**
 * Raw Battery NativeModule transport contract.
 *
 * The native API intentionally keeps callbacks; high-level Promise and
 * runtime validation live in @lynx-app/native-bridge.
 *
 * @lynxmodule
 */
export declare class Battery {
  getInfo(callback: (resultJSON: string) => void): void;
}
