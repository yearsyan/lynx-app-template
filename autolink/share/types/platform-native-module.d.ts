/**
 * Raw Share NativeModule transport contract.
 *
 * The native API intentionally keeps callbacks; this package's src/index.ts
 * owns the high-level Promise API and runtime validation.
 *
 * @lynxmodule
 */
export declare class Share {
  share(
    options: {
      title: string | null;
      text: string | null;
      url: string | null;
      files: string[];
    },
    callback: (resultJSON: string) => void,
  ): void;
}
