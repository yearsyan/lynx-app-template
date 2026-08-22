/**
 * Raw Navigation NativeModule transport contract: route navigation plus the
 * Back interceptor stack in one module.
 *
 * The native API intentionally keeps callbacks; this package's src/index.ts
 * owns the high-level Promise API and runtime validation.
 *
 * @lynxmodule
 */
export declare class Navigation {
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
  setEnabled(enabled: boolean, callback: (error: string) => void): void;
  configure(
    enabled: boolean,
    interceptorId: string,
    targetId: string,
    revision: number,
    callback: (error: string) => void,
  ): void;
}
