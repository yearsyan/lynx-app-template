/**
 * Raw LocalNotification NativeModule transport contract.
 *
 * The native API intentionally keeps callbacks; this package's src/index.ts
 * owns the high-level Promise API and runtime validation.
 *
 * @lynxmodule
 */
export declare class LocalNotification {
  notify(
    options: {
      id: string;
      title: string;
      body: string;
      delayMs: number;
      sound: boolean;
    },
    callback: (result: {
      value?: {
        code: 'success' | 'permissionDenied' | 'unavailable';
        message: string;
      };
      error?: string;
    }) => void,
  ): void;
  cancel(id: string, callback: (error: string) => void): void;
  cancelAll(callback: (error: string) => void): void;
}
