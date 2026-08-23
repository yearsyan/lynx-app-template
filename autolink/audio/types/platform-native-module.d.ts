/**
 * Raw Audio NativeModule transport contract.
 *
 * Playback is local-file only: the URI must be a local `file://` (or, on
 * Android, a `content://`) source, typically the output of the FileSystem
 * or AlbumUtils modules. Recording captures the microphone to an AAC file
 * under the host cache directory; the microphone permission is expected to
 * be granted already (request it through the Permissions module first).
 * Commands use error-string acknowledgements; playback events arrive as
 * `audioPlayer` and recording events as `audioRecorder` global events. The
 * package's src/index.ts owns the high-level Promise API and runtime
 * validation.
 *
 * @lynxmodule
 */
export declare class Audio {
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
  recorderCreate(
    options: {
      id: string;
      /** 0 disables the automatic duration cap. */
      durationLimitMs: number;
      progressIntervalMs: number;
    },
    callback: (error: string) => void,
  ): void;
  recorderStart(id: string, callback: (error: string) => void): void;
  recorderPause(id: string, callback: (error: string) => void): void;
  recorderResume(id: string, callback: (error: string) => void): void;
  recorderStop(id: string, callback: (resultJSON: string) => void): void;
  recorderCancel(id: string, callback: (error: string) => void): void;
  recorderGetProps(id: string, callback: (resultJSON: string) => void): void;
  recorderRelease(id: string, callback: (error: string) => void): void;
}
