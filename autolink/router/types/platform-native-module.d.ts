/**
 * Raw Router NativeModule transport contract.
 *
 * The native API intentionally keeps callbacks; high-level Promise and
 * runtime validation live in @lynx-app/native-bridge.
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
