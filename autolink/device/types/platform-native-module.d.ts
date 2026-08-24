/**
 * Raw Device NativeModule transport contract: device facts, safe area,
 * status bar, display metrics, battery state, streaming sensors
 * (accelerometer, compass, gyroscope, magnetometer and barometer).
 *
 * The native API intentionally keeps callbacks; this package's src/index.ts
 * owns the high-level Promise API and runtime validation.
 *
 * @lynxmodule
 */
export declare class Device {
  getInfo(callback: (resultJSON: string) => void): void;
  getSafeAreaInsets(callback: (resultJSON: string) => void): void;
  setStatusBarStyle(
    style: 'dark-content' | 'light-content',
    callback: (error: string) => void,
  ): void;
  screenWidth(callback: (resultJSON: string) => void): void;
  windowWidth(callback: (resultJSON: string) => void): void;
  lynxViewWidth(callback: (resultJSON: string) => void): void;
  getBrightness(callback: (resultJSON: string) => void): void;
  setBrightness(value: number, callback: (error: string) => void): void;
  setKeepScreenOn(enabled: boolean, callback: (error: string) => void): void;
  openAppSettings(callback: (error: string) => void): void;
  getBatteryInfo(
    callback: (result: {
      value?: { level: number | null; charging: boolean };
      error?: string;
    }) => void,
  ): void;
  isAvailable(type: string, callback: (resultJSON: string) => void): void;
  start(type: string, callback: (error: string) => void): void;
  stop(type: string, callback: (error: string) => void): void;
}
