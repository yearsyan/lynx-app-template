/**
 * Raw Screenshot NativeModule transport contract.
 *
 * The native API intentionally keeps callbacks; this package's src/index.ts
 * owns the high-level Promise API and runtime validation.
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
