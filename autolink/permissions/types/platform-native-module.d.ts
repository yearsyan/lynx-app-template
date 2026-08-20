/**
 * Raw Permissions NativeModule transport contract.
 *
 * The native API intentionally keeps callbacks; this package's src/index.ts
 * owns the high-level Promise API and runtime validation.
 *
 * @lynxmodule
 */
export declare class Permissions {
  check(
    permission: {
      type: 'notifications' | 'camera' | 'photoLibrary' | 'microphone';
    },
    callback: (result: {
      value?: {
        status:
          | 'granted'
          | 'limited'
          | 'denied'
          | 'notDetermined'
          | 'restricted';
      };
      error?: string;
    }) => void,
  ): void;
  request(
    permission: {
      type: 'notifications' | 'camera' | 'photoLibrary' | 'microphone';
    },
    callback: (result: {
      value?: {
        status:
          | 'granted'
          | 'limited'
          | 'denied'
          | 'notDetermined'
          | 'restricted';
      };
      error?: string;
    }) => void,
  ): void;
}
