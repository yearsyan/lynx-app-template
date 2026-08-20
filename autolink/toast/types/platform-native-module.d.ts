/**
 * Raw Toast NativeModule transport contract.
 *
 * The native API intentionally keeps callbacks; this package's src/index.ts
 * owns the high-level Promise API and runtime validation.
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
