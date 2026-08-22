/**
 * Raw ImageTooling NativeModule transport contract.
 *
 * The native API intentionally keeps callbacks; this package's src/index.ts
 * owns the high-level Promise API and runtime validation.
 *
 * @lynxmodule
 */
export declare class ImageTooling {
  info(uri: string, callback: (resultJSON: string) => void): void;
  compress(
    options: {
      uri: string;
      maxWidth: number | null;
      maxHeight: number | null;
      quality: number;
      format: 'jpeg' | 'png';
    },
    callback: (resultJSON: string) => void,
  ): void;
  crop(
    options: {
      uri: string;
      x: number;
      y: number;
      width: number;
      height: number;
      maxWidth: number | null;
      maxHeight: number | null;
      quality: number;
      format: 'jpeg' | 'png';
    },
    callback: (resultJSON: string) => void,
  ): void;
  compose(
    options: {
      images: Array<{
        uri: string;
        x: number;
        y: number;
        opacity: number;
      }>;
      layout: 'horizontal' | 'vertical' | 'overlay';
      spacing: number;
      maxWidth: number | null;
      maxHeight: number | null;
      quality: number;
      format: 'jpeg' | 'png';
    },
    callback: (resultJSON: string) => void,
  ): void;
  readExif(uri: string, callback: (resultJSON: string) => void): void;
  writeExif(
    options: {
      uri: string;
      tags: Record<string, string | null>;
      gps?: {
        latitude: number;
        longitude: number;
        altitude?: number | null;
      } | null;
    },
    callback: (resultJSON: string) => void,
  ): void;
  removeExif(
    options: {
      uri: string;
      quality: number;
      format: 'jpeg' | 'png' | null;
    },
    callback: (resultJSON: string) => void,
  ): void;
}
