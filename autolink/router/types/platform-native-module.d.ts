/**
 * Raw Router NativeModule transport contract.
 *
 * The native API intentionally keeps callbacks; this package's src/index.ts
 * owns the high-level Promise API and runtime validation.
 *
 * @lynxmodule
 */
export declare class Router {
  open(
    options: {
      bundle: string;
      presentation?: 'push' | 'sheet';
      transparent?: boolean;
      statusBarStyle?: 'dark-content' | 'light-content';
      animation?: 'default' | 'fade' | 'none';
      params?: Record<string, unknown>;
    },
    callback: (error: string) => void,
  ): void;
  close(callback: (error: string) => void): void;
  openURL(url: string, callback: (error: string) => void): void;
}
