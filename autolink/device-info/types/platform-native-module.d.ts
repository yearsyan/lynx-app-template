/**
 * Raw DeviceInfo NativeModule transport contract.
 *
 * The native API intentionally keeps callbacks; this package's src/index.ts
 * owns the high-level Promise API and runtime validation.
 *
 * @lynxmodule
 */
export declare class DeviceInfo {
  getInfo(callback: (resultJSON: string) => void): void;
  getSafeAreaInsets(callback: (resultJSON: string) => void): void;
  setStatusBarStyle(
    style: 'dark-content' | 'light-content',
    callback: (error: string) => void,
  ): void;
}
