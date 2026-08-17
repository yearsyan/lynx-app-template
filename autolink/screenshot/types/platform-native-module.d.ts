/**
 * Raw Screenshot NativeModule transport contract.
 *
 * The native API intentionally keeps callbacks; high-level Promise and
 * runtime validation live in @lynx-app/native-bridge.
 *
 * @lynxmodule
 */
export declare class Screenshot {
  capture(
    options: {
      idSelector: string | null;
      format: 'png' | 'jpeg';
      quality: number;
      fileName: string | null;
    },
    callback: (resultJSON: string) => void,
  ): void;
  capturePage(
    options: {
      idSelector: string | null;
      format: 'png' | 'jpeg';
      quality: number;
      fileName: string | null;
    },
    callback: (resultJSON: string) => void,
  ): void;
}
