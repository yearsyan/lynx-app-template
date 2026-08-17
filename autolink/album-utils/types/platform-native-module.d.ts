/**
 * Raw AlbumUtils NativeModule transport contract.
 *
 * The native API intentionally keeps callbacks; high-level Promise and
 * runtime validation live in @lynx-app/native-bridge.
 *
 * @lynxmodule
 */
export declare class AlbumUtils {
  pick(maxSelection: number, callback: (resultJSON: string) => void): void;
  saveToAlbum(uri: string, callback: (error: string) => void): void;
}
