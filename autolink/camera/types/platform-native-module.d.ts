/** Options accepted by the platform system-camera picker. */
export interface NativeCameraOptions {
  /** Preferred camera. Hosts fall back to their default when unavailable. */
  lens?: string;
}

/**
 * Raw Camera NativeModule transport contract.
 *
 * The public Promise facade and runtime validation live in src/index.ts.
 * Hosts return a JSON-compatible envelope so user cancellation remains a
 * normal outcome rather than a rejected bridge call.
 *
 * @lynxmodule
 */
export declare class Camera {
  takePhoto(
    options: NativeCameraOptions,
    callback: (resultJSON: string) => void,
  ): void;
}
