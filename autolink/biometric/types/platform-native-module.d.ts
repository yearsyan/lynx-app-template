/**
 * Raw Biometric NativeModule transport contract.
 *
 * The native API intentionally keeps callbacks; this package's src/index.ts
 * owns the high-level Promise API and runtime validation.
 *
 * @lynxmodule
 */
export declare class Biometric {
  checkSupport(callback: (resultJSON: string) => void): void;
  authenticate(
    optionsJSON: string,
    callback: (resultJSON: string) => void,
  ): void;
  createSigningKey(callback: (resultJSON: string) => void): void;
  signChallenge(
    optionsJSON: string,
    callback: (resultJSON: string) => void,
  ): void;
}
