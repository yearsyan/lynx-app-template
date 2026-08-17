/**
 * Raw Display NativeModule transport contract.
 *
 * The native API intentionally keeps callbacks; high-level Promise and
 * runtime validation live in @lynx-app/native-bridge.
 *
 * @lynxmodule
 */
export declare class Display {
  screenWidth(callback: (resultJSON: string) => void): void;
  windowWidth(callback: (resultJSON: string) => void): void;
  lynxViewWidth(callback: (resultJSON: string) => void): void;
  getBrightness(callback: (resultJSON: string) => void): void;
  setBrightness(value: number, callback: (error: string) => void): void;
  setKeepScreenOn(enabled: boolean, callback: (error: string) => void): void;
}
