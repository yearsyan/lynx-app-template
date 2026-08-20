/**
 * Raw Battery NativeModule transport contract.
 *
 * The native API intentionally keeps callbacks; this package's src/index.ts
 * owns the high-level Promise API and runtime validation.
 *
 * @lynxmodule
 */
export declare class Battery {
  getInfo(
    callback: (result: {
      value?: { level: number | null; charging: boolean };
      error?: string;
    }) => void,
  ): void;
}
