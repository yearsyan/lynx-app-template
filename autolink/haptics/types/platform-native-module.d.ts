/**
 * Raw Haptics NativeModule transport contract.
 *
 * The native API intentionally keeps callbacks; high-level Promise and
 * runtime validation live in @lynx-app/native-bridge.
 *
 * @lynxmodule
 */
export declare class Haptics {
  impact(
    style: 'light' | 'medium' | 'heavy',
    callback: (error: string) => void,
  ): void;
}
