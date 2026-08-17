/**
 * Raw Biometric NativeModule transport contract.
 *
 * The native API intentionally keeps callbacks; high-level Promise and
 * runtime validation live in @lynx-app/native-bridge.
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
