/**
 * Raw Back NativeModule transport contract.
 *
 * The native API keeps the platform decision synchronous while this package's
 * TypeScript facade owns Promise conversion, event validation and the LIFO
 * interceptor stack.
 *
 * @lynxmodule
 */
export declare class Back {
  setEnabled(enabled: boolean, callback: (error: string) => void): void;
  configure(
    enabled: boolean,
    interceptorId: string,
    targetId: string,
    revision: number,
    callback: (error: string) => void,
  ): void;
}
