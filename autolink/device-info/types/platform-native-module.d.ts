/**
 * Raw DeviceInfo NativeModule transport contract.
 *
 * The native API intentionally keeps callbacks; high-level Promise and
 * runtime validation live in @lynx-app/native-bridge.
 *
 * @lynxmodule
 */
export declare class DeviceInfo {
  getInfo(callback: (resultJSON: string) => void): void;
}
