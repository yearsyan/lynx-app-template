/**
 * Native image metadata, resize/crop/composition and EXIF tooling. Image
 * pixels stay native-side; every operation that writes returns a new file in
 * `<cache>/LynxImages/` and never mutates the source URI.
 */
import {
  decodeNativeEnvelope,
  requireNativeModule,
} from './bridge.generated.js';
import type { ImageToolingModule } from './native.generated.js';

export * from './native.generated.js';

export type ImageFormat = 'jpeg' | 'png';
export type ComposeLayout = 'horizontal' | 'vertical' | 'overlay';

export interface ImageInfo {
  /** Pixel width after applying EXIF orientation. */
  width: number;
  /** Pixel height after applying EXIF orientation. */
  height: number;
  /** Detected MIME type, e.g. `image/jpeg`; null when undetectable. */
  mimeType: string | null;
  /** Source size in bytes; null when the provider cannot report it. */
  sizeBytes: number | null;
}

export interface ImageOutput {
  /** `file://` URI of the output inside the app cache directory. */
  uri: string;
  width: number;
  height: number;
  sizeBytes: number;
}

/** Backward-compatible name used by the original compress API. */
export interface CompressResult extends ImageOutput {}

interface EncodingOptions {
  /** JPEG quality from 1 to 100. Ignored for PNG. Defaults to 80. */
  quality?: number;
  /** Output format. Defaults to `jpeg`. */
  format?: ImageFormat;
}

interface BoundedOutputOptions {
  /** Maximum output width. The operation never upscales. */
  maxWidth?: number;
  /** Maximum output height. The operation never upscales. */
  maxHeight?: number;
}

export interface CompressOptions extends EncodingOptions, BoundedOutputOptions {
  /** Image URI (`content://` on Android or `file://`). */
  uri: string;
}

export interface CropOptions extends EncodingOptions, BoundedOutputOptions {
  uri: string;
  /** Crop rectangle in oriented/display pixels. */
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface ComposeImage {
  uri: string;
  /** Overlay-only X offset in output pixels. Defaults to 0. */
  x?: number;
  /** Overlay-only Y offset in output pixels. Defaults to 0. */
  y?: number;
  /** Layer opacity from 0 to 1. Defaults to 1. */
  opacity?: number;
}

export interface ComposeOptions extends EncodingOptions, BoundedOutputOptions {
  /** One to sixteen input layers. Later overlay layers paint above earlier ones. */
  images: ReadonlyArray<string | ComposeImage>;
  layout: ComposeLayout;
  /** Gap between horizontal/vertical images in pixels. Defaults to 0. */
  spacing?: number;
}

/** Canonical EXIF tags supported consistently by all three native hosts. */
export const EXIF_TAGS = [
  'Orientation',
  'ImageDescription',
  'Make',
  'Model',
  'Software',
  'Artist',
  'Copyright',
  'DateTime',
  'DateTimeOriginal',
  'OffsetTimeOriginal',
  'UserComment',
  'ExposureTime',
  'FNumber',
  'ISOSpeedRatings',
  'FocalLength',
  'LensMake',
  'LensModel',
] as const;

export type ExifTag = (typeof EXIF_TAGS)[number];
export type ExifTags = Partial<Record<ExifTag, string>>;
export type ExifUpdates = Partial<Record<ExifTag, string | null>>;

export interface ExifGPS {
  latitude: number;
  longitude: number;
  /**
   * Meters above sea level; negative values mean below sea level. When
   * writing, omit to preserve an existing altitude or use null to delete it.
   */
  altitude?: number | null;
}

export interface ExifInfo {
  tags: ExifTags;
  gps: ExifGPS | null;
}

export interface WriteExifOptions {
  uri: string;
  /** String writes/replaces a tag; null deletes that tag. */
  tags?: ExifUpdates;
  /** Object writes GPS; null removes all GPS fields; omit to preserve GPS. */
  gps?: ExifGPS | null;
}

export interface RemoveExifOptions {
  uri: string;
  /** JPEG quality used by the metadata-stripping re-encode. Defaults to 100. */
  quality?: number;
  /** Defaults to the source format for JPEG/PNG, otherwise JPEG. */
  format?: ImageFormat;
}

interface NativeEncodingRequest {
  quality: number;
  format: ImageFormat;
  maxWidth: number | null;
  maxHeight: number | null;
}

interface NativeValueResult {
  error?: unknown;
  value?: unknown;
}

const DEFAULT_JPEG_QUALITY = 80;
const MAX_DIMENSION = 16384;
const MAX_IMAGES = 16;
const MAX_SPACING = 4096;
const MAX_EXIF_VALUE_LENGTH = 4096;
const EXIF_TAG_SET = new Set<string>(EXIF_TAGS);

function requireImageToolingModule(): ImageToolingModule {
  'background only';
  return requireNativeModule();
}

function normalizeUri(uri: string): string {
  'background only';
  if (typeof uri !== 'string' || uri.trim().length === 0) {
    throw new Error('ImageTooling requires a non-empty image URI');
  }
  const normalized = uri.trim();
  if (
    !normalized.startsWith('content://') &&
    !normalized.startsWith('file://')
  ) {
    throw new Error('ImageTooling supports content:// and file:// image URIs');
  }
  return normalized;
}

function normalizeDimension(value: number, label: string): number {
  'background only';
  if (!Number.isInteger(value) || value < 1 || value > MAX_DIMENSION) {
    throw new Error(
      `ImageTooling ${label} must be an integer from 1 to ${MAX_DIMENSION}`,
    );
  }
  return value;
}

function normalizeNonNegativeInteger(value: number, label: string): number {
  'background only';
  if (!Number.isSafeInteger(value) || value < 0) {
    throw new Error(`ImageTooling ${label} must be a non-negative integer`);
  }
  return value;
}

function normalizeQuality(
  value: number | undefined,
  fallback = DEFAULT_JPEG_QUALITY,
) {
  'background only';
  const quality = value ?? fallback;
  if (!Number.isInteger(quality) || quality < 1 || quality > 100) {
    throw new Error('ImageTooling quality must be an integer from 1 to 100');
  }
  return quality;
}

function normalizeFormat(value: ImageFormat | undefined): ImageFormat {
  'background only';
  const format = value ?? 'jpeg';
  if (format !== 'jpeg' && format !== 'png') {
    throw new Error(`Invalid ImageTooling format: ${String(format)}`);
  }
  return format;
}

function normalizeEncoding(
  options: EncodingOptions & BoundedOutputOptions,
): NativeEncodingRequest {
  'background only';
  return {
    maxWidth:
      options.maxWidth === undefined
        ? null
        : normalizeDimension(options.maxWidth, 'maxWidth'),
    maxHeight:
      options.maxHeight === undefined
        ? null
        : normalizeDimension(options.maxHeight, 'maxHeight'),
    quality: normalizeQuality(options.quality),
    format: normalizeFormat(options.format),
  };
}

function isPositiveSafeInteger(value: unknown): value is number {
  return typeof value === 'number' && Number.isSafeInteger(value) && value >= 1;
}

function decodeInfo(value: unknown): ImageInfo {
  'background only';
  if (typeof value !== 'object' || value === null) {
    throw new Error('ImageTooling returned an invalid info result');
  }
  const result = value as Partial<ImageInfo>;
  if (
    !isPositiveSafeInteger(result.width) ||
    !isPositiveSafeInteger(result.height)
  ) {
    throw new Error('ImageTooling returned an invalid info result');
  }
  return {
    width: result.width,
    height: result.height,
    mimeType:
      typeof result.mimeType === 'string' && result.mimeType.length > 0
        ? result.mimeType
        : null,
    sizeBytes:
      typeof result.sizeBytes === 'number' &&
      Number.isSafeInteger(result.sizeBytes) &&
      result.sizeBytes >= 0
        ? result.sizeBytes
        : null,
  };
}

function decodeImageOutput(value: unknown): ImageOutput {
  'background only';
  if (typeof value !== 'object' || value === null) {
    throw new Error('ImageTooling returned an invalid image result');
  }
  const result = value as Partial<ImageOutput>;
  if (
    typeof result.uri !== 'string' ||
    result.uri.length === 0 ||
    !isPositiveSafeInteger(result.width) ||
    !isPositiveSafeInteger(result.height) ||
    typeof result.sizeBytes !== 'number' ||
    !Number.isSafeInteger(result.sizeBytes) ||
    result.sizeBytes < 1
  ) {
    throw new Error('ImageTooling returned an invalid image result');
  }
  return result as ImageOutput;
}

function decodeExif(value: unknown): ExifInfo {
  'background only';
  if (typeof value !== 'object' || value === null) {
    throw new Error('ImageTooling returned invalid EXIF data');
  }
  const raw = value as { tags?: unknown; gps?: unknown };
  if (
    typeof raw.tags !== 'object' ||
    raw.tags === null ||
    Array.isArray(raw.tags)
  ) {
    throw new Error('ImageTooling returned invalid EXIF tags');
  }
  const tags: ExifTags = {};
  for (const [key, tagValue] of Object.entries(raw.tags)) {
    if (EXIF_TAG_SET.has(key) && typeof tagValue === 'string') {
      tags[key as ExifTag] = tagValue;
    }
  }
  if (raw.gps === null || raw.gps === undefined) {
    return { tags, gps: null };
  }
  if (typeof raw.gps !== 'object' || Array.isArray(raw.gps)) {
    throw new Error('ImageTooling returned invalid EXIF GPS data');
  }
  const gps = raw.gps as Partial<ExifGPS>;
  if (
    typeof gps.latitude !== 'number' ||
    !Number.isFinite(gps.latitude) ||
    gps.latitude < -90 ||
    gps.latitude > 90 ||
    typeof gps.longitude !== 'number' ||
    !Number.isFinite(gps.longitude) ||
    gps.longitude < -180 ||
    gps.longitude > 180 ||
    (gps.altitude !== undefined &&
      gps.altitude !== null &&
      (typeof gps.altitude !== 'number' || !Number.isFinite(gps.altitude)))
  ) {
    throw new Error('ImageTooling returned invalid EXIF GPS data');
  }
  return { tags, gps: gps as ExifGPS };
}

function invoke<T>(
  action: (callback: (result: unknown) => void) => void,
  decode: (value: unknown) => T,
): Promise<T> {
  'background only';
  return new Promise((resolve, reject) => {
    try {
      action((resultValue) => {
        'background only';
        try {
          const result = decodeNativeEnvelope(
            resultValue,
            'ImageTooling',
          ) as NativeValueResult;
          if (typeof result.error === 'string' && result.error.length > 0) {
            reject(new Error(result.error));
            return;
          }
          resolve(decode(result.value));
        } catch (error) {
          reject(error instanceof Error ? error : new Error(String(error)));
        }
      });
    } catch (error) {
      reject(error instanceof Error ? error : new Error(String(error)));
    }
  });
}

function normalizeGPS(gps: ExifGPS): ExifGPS {
  'background only';
  if (
    typeof gps !== 'object' ||
    gps === null ||
    typeof gps.latitude !== 'number' ||
    !Number.isFinite(gps.latitude) ||
    gps.latitude < -90 ||
    gps.latitude > 90 ||
    typeof gps.longitude !== 'number' ||
    !Number.isFinite(gps.longitude) ||
    gps.longitude < -180 ||
    gps.longitude > 180
  ) {
    throw new Error('ImageTooling GPS coordinates are invalid');
  }
  if (
    gps.altitude !== undefined &&
    gps.altitude !== null &&
    (typeof gps.altitude !== 'number' || !Number.isFinite(gps.altitude))
  ) {
    throw new Error('ImageTooling GPS altitude must be finite or null');
  }
  return {
    latitude: gps.latitude,
    longitude: gps.longitude,
    ...(gps.altitude === undefined ? {} : { altitude: gps.altitude }),
  };
}

/** Native image operations. */
export const imageTooling = {
  info(uri: string): Promise<ImageInfo> {
    'background only';
    return invoke(
      (callback) =>
        requireImageToolingModule().info(normalizeUri(uri), callback),
      decodeInfo,
    );
  },

  /** Proportionally downscales and re-encodes the entire image. */
  compress(options: CompressOptions): Promise<CompressResult> {
    'background only';
    if (typeof options !== 'object' || options === null) {
      throw new Error('ImageTooling compress requires an options object');
    }
    const request = {
      uri: normalizeUri(options.uri),
      ...normalizeEncoding(options),
    };
    return invoke(
      (callback) => requireImageToolingModule().compress(request, callback),
      decodeImageOutput,
    );
  },

  /** Crops one oriented/display-space rectangle, then optionally downscales. */
  crop(options: CropOptions): Promise<ImageOutput> {
    'background only';
    if (typeof options !== 'object' || options === null) {
      throw new Error('ImageTooling crop requires an options object');
    }
    const request = {
      uri: normalizeUri(options.uri),
      x: normalizeNonNegativeInteger(options.x, 'crop x'),
      y: normalizeNonNegativeInteger(options.y, 'crop y'),
      width: normalizeDimension(options.width, 'crop width'),
      height: normalizeDimension(options.height, 'crop height'),
      ...normalizeEncoding(options),
    };
    return invoke(
      (callback) => requireImageToolingModule().crop(request, callback),
      decodeImageOutput,
    );
  },

  /** Joins images horizontally/vertically or paints them as ordered layers. */
  compose(options: ComposeOptions): Promise<ImageOutput> {
    'background only';
    if (typeof options !== 'object' || options === null) {
      throw new Error('ImageTooling compose requires an options object');
    }
    if (
      !Array.isArray(options.images) ||
      options.images.length < 1 ||
      options.images.length > MAX_IMAGES
    ) {
      throw new Error(`ImageTooling compose requires 1-${MAX_IMAGES} images`);
    }
    if (
      options.layout !== 'horizontal' &&
      options.layout !== 'vertical' &&
      options.layout !== 'overlay'
    ) {
      throw new Error(`Invalid ImageTooling layout: ${String(options.layout)}`);
    }
    const spacing = options.spacing ?? 0;
    if (!Number.isInteger(spacing) || spacing < 0 || spacing > MAX_SPACING) {
      throw new Error(
        `ImageTooling spacing must be an integer from 0 to ${MAX_SPACING}`,
      );
    }
    const images = options.images.map((entry, index) => {
      const layer: ComposeImage =
        typeof entry === 'string' ? { uri: entry } : entry;
      if (typeof layer !== 'object' || layer === null) {
        throw new Error(`ImageTooling image ${index} is invalid`);
      }
      const opacity = layer.opacity ?? 1;
      if (
        typeof opacity !== 'number' ||
        !Number.isFinite(opacity) ||
        opacity < 0 ||
        opacity > 1
      ) {
        throw new Error(
          `ImageTooling image ${index} opacity must be from 0 to 1`,
        );
      }
      return {
        uri: normalizeUri(layer.uri),
        x: normalizeNonNegativeInteger(layer.x ?? 0, `image ${index} x`),
        y: normalizeNonNegativeInteger(layer.y ?? 0, `image ${index} y`),
        opacity,
      };
    });
    const request = {
      images,
      layout: options.layout,
      spacing,
      ...normalizeEncoding(options),
    };
    return invoke(
      (callback) => requireImageToolingModule().compose(request, callback),
      decodeImageOutput,
    );
  },

  /** Reads the cross-platform EXIF subset plus normalized decimal GPS. */
  readExif(uri: string): Promise<ExifInfo> {
    'background only';
    return invoke(
      (callback) =>
        requireImageToolingModule().readExif(normalizeUri(uri), callback),
      decodeExif,
    );
  },

  /** Writes EXIF into a copied cache file; null values remove fields. */
  writeExif(options: WriteExifOptions): Promise<ImageOutput> {
    'background only';
    if (typeof options !== 'object' || options === null) {
      throw new Error('ImageTooling writeExif requires an options object');
    }
    const tags: Record<string, string | null> = {};
    if (options.tags !== undefined) {
      if (typeof options.tags !== 'object' || options.tags === null) {
        throw new Error('ImageTooling EXIF tags must be an object');
      }
      for (const [key, value] of Object.entries(options.tags)) {
        if (!EXIF_TAG_SET.has(key)) {
          throw new Error(`Unsupported ImageTooling EXIF tag: ${key}`);
        }
        if (
          value !== null &&
          (typeof value !== 'string' || value.length > MAX_EXIF_VALUE_LENGTH)
        ) {
          throw new Error(
            `ImageTooling EXIF ${key} must be a string up to ${MAX_EXIF_VALUE_LENGTH} characters or null`,
          );
        }
        tags[key] = value;
      }
    }
    const hasGPS = options.gps !== undefined;
    if (Object.keys(tags).length === 0 && !hasGPS) {
      throw new Error('ImageTooling writeExif requires tags or gps changes');
    }
    const request: {
      uri: string;
      tags: Record<string, string | null>;
      gps?: ExifGPS | null;
    } = { uri: normalizeUri(options.uri), tags };
    if (hasGPS) {
      request.gps =
        options.gps === null ? null : normalizeGPS(options.gps as ExifGPS);
    }
    return invoke(
      (callback) => requireImageToolingModule().writeExif(request, callback),
      decodeImageOutput,
    );
  },

  /** Re-encodes upright pixels into a new file with all EXIF/GPS removed. */
  removeExif(options: RemoveExifOptions): Promise<ImageOutput> {
    'background only';
    if (typeof options !== 'object' || options === null) {
      throw new Error('ImageTooling removeExif requires an options object');
    }
    const request = {
      uri: normalizeUri(options.uri),
      quality: normalizeQuality(options.quality, 100),
      format:
        options.format === undefined ? null : normalizeFormat(options.format),
    };
    return invoke(
      (callback) => requireImageToolingModule().removeExif(request, callback),
      decodeImageOutput,
    );
  },
};
