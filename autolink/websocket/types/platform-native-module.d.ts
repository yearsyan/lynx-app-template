/**
 * Raw WebSocket NativeModule transport contract.
 *
 * The native API intentionally keeps callbacks; high-level Promise and
 * runtime validation live in @lynx-app/native-bridge.
 *
 * @lynxmodule
 */
export declare class WebSocket {
  connect(
    options: {
      id: string;
      url: string;
      protocols: string[];
      headers: Record<string, string>;
    },
    callback: (error: string) => void,
  ): void;
  sendText(id: string, data: string, callback: (error: string) => void): void;
  sendBase64(id: string, data: string, callback: (error: string) => void): void;
  close(
    id: string,
    code: number,
    reason: string,
    callback: (error: string) => void,
  ): void;
}
