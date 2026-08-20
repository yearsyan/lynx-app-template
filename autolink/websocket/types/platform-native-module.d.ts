/**
 * Raw WebSocket NativeModule transport contract.
 *
 * The native API intentionally keeps callbacks; this package's src/index.ts
 * owns the high-level Promise API and runtime validation.
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
