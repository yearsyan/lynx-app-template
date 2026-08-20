/**
 * Raw AudioPlayer NativeModule transport contract.
 *
 * Local-file playback only: the URI must be a local `file://` (or, on
 * Android, a `content://`) source, typically the output of the FileSystem
 * or AlbumUtils modules. Commands use error-string acknowledgements;
 * state changes plus throttled progress arrive as `audioPlayer` global
 * events. High-level Promise and runtime validation live in
 * @lynx-app/native-bridge.
 *
 * @lynxmodule
 */
export declare class AudioPlayer {
  create(
    options: {
      id: string;
      uri: string;
      /** 'media' | 'ambient' | 'alarm' | 'notification'. */
      usage: string;
      autoPlay: boolean;
      progressIntervalMs: number;
    },
    callback: (error: string) => void,
  ): void;
  play(id: string, callback: (error: string) => void): void;
  pause(id: string, callback: (error: string) => void): void;
  seek(id: string, positionMs: number, callback: (error: string) => void): void;
  stop(id: string, callback: (error: string) => void): void;
  release(id: string, callback: (error: string) => void): void;
  setRate(id: string, rate: number, callback: (error: string) => void): void;
  setVolume(
    id: string,
    volume: number,
    callback: (error: string) => void,
  ): void;
  getProps(id: string, callback: (resultJSON: string) => void): void;
}
