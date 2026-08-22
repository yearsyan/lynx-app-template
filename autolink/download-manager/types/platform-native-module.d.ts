/**
 * Raw DownloadManager NativeModule transport contract.
 *
 * Commands return JSON envelopes so all three native hosts can preserve
 * nullable fields and 64-bit byte counts consistently. Progress and state
 * changes are emitted through the `downloadManager` global event.
 *
 * @lynxmodule
 */
export declare class DownloadManager {
  getCapabilities(callback: (resultJSON: string) => void): void;
  enqueue(
    options: {
      id: string;
      url: string;
      fileName: string;
      headers: Record<string, string>;
      progressIntervalMs: number;
      persistProgress: boolean;
      androidForegroundService: boolean;
      notificationTitle: string;
      notificationText: string;
    },
    callback: (resultJSON: string) => void,
  ): void;
  pause(id: string, callback: (resultJSON: string) => void): void;
  resume(id: string, callback: (resultJSON: string) => void): void;
  cancel(id: string, callback: (resultJSON: string) => void): void;
  remove(
    id: string,
    deleteFile: boolean,
    callback: (resultJSON: string) => void,
  ): void;
  getTask(id: string, callback: (resultJSON: string) => void): void;
  listTasks(callback: (resultJSON: string) => void): void;
}
