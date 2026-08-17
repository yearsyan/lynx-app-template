/**
 * Raw Toast NativeModule transport contract.
 *
 * The native API intentionally keeps callbacks; high-level Promise and
 * runtime validation live in @lynx-app/native-bridge.
 *
 * @lynxmodule
 */
export declare class Toast {
  show(
    message: string,
    options: {
      type: 'info' | 'success' | 'error';
      showIcon: boolean;
      backgroundColor?: string;
      textColor?: string;
      durationMs: number;
    },
    callback: (error: string) => void,
  ): void;
}
