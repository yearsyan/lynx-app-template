/**
 * Raw Haptics NativeModule transport contract.
 *
 * The native API intentionally keeps callbacks; this package's src/index.ts
 * owns the high-level Promise API and runtime validation.
 *
 * @lynxmodule
 */
export declare class Haptics {
  impact(
    style: 'light' | 'medium' | 'heavy',
    callback: (error: string) => void,
  ): void;
}
