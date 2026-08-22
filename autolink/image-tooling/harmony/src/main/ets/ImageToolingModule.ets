import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { LynxContext, LynxModule } from '@lynx/lynx';

export interface NativeEncodingOptions {
  uri?: string;
  maxWidth?: number | null;
  maxHeight?: number | null;
  quality?: number;
  format?: string | null;
}

export interface NativeCropOptions extends NativeEncodingOptions {
  x?: number;
  y?: number;
  width?: number;
  height?: number;
}

export interface NativeComposeImage {
  uri?: string;
  x?: number;
  y?: number;
  opacity?: number;
}

export interface NativeComposeOptions {
  images?: Array<NativeComposeImage>;
  layout?: string;
  spacing?: number;
  maxWidth?: number | null;
  maxHeight?: number | null;
  quality?: number;
  format?: string;
}

export interface NativeGPSUpdate {
  latitude?: number;
  longitude?: number;
  altitude?: number | null;
}

export interface NativeExifWriteOptions {
  uri?: string;
  tags?: Record<string, string | null>;
  gps?: NativeGPSUpdate | null;
}

class EncodingRequest {
  uri: string = '';
  maxWidth: number = 0;
  maxHeight: number = 0;
  quality: number = 80;
  jpeg: boolean = true;
}

class CropRequest extends EncodingRequest {
  x: number = 0;
  y: number = 0;
  width: number = 0;
  height: number = 0;
}

class ComposeLayer {
  uri: string = '';
  x: number = 0;
  y: number = 0;
  opacity: number = 1.0;
}

class ComposeRequest {
  layers: Array<ComposeLayer> = [];
  layout: string = '';
  spacing: number = 0;
  maxWidth: number = 0;
  maxHeight: number = 0;
  quality: number = 80;
  jpeg: boolean = true;
}

class RemoveExifRequest extends EncodingRequest {
  formatSpecified: boolean = false;
}

class SourceDescriptor {
  uri: string;
  rawWidth: number;
  rawHeight: number;
  displayWidth: number;
  displayHeight: number;
  orientation: string;
  mimeType: string | null;
  sizeBytes: number | null;

  constructor(
    uri: string,
    rawWidth: number,
    rawHeight: number,
    orientation: string,
    mimeType: string | null,
    sizeBytes: number | null,
  ) {
    this.uri = uri;
    this.rawWidth = rawWidth;
    this.rawHeight = rawHeight;
    this.orientation = orientation;
    const quarterTurn = orientation === 'Left-top' || orientation === 'Right-top'
      || orientation === 'Right-bottom' || orientation === 'Left-bottom';
    this.displayWidth = quarterTurn ? rawHeight : rawWidth;
    this.displayHeight = quarterTurn ? rawWidth : rawHeight;
    this.mimeType = mimeType;
    this.sizeBytes = sizeBytes;
  }
}

class InfoValue {
  width: number;
  height: number;
  mimeType: string | null;
  sizeBytes: number | null;

  constructor(source: SourceDescriptor) {
    this.width = source.displayWidth;
    this.height = source.displayHeight;
    this.mimeType = source.mimeType;
    this.sizeBytes = source.sizeBytes;
  }
}

class ImageValue {
  uri: string;
  width: number;
  height: number;
  sizeBytes: number;

  constructor(uri: string, width: number, height: number, sizeBytes: number) {
    this.uri = uri;
    this.width = width;
    this.height = height;
    this.sizeBytes = sizeBytes;
  }
}

class GPSValue {
  latitude: number;
  longitude: number;
  altitude?: number | null;

  constructor(latitude: number, longitude: number, altitude?: number | null) {
    this.latitude = latitude;
    this.longitude = longitude;
    if (altitude !== undefined) {
      this.altitude = altitude;
    }
  }
}

class ExifValue {
  tags: Record<string, string>;
  gps: GPSValue | null;

  constructor(tags: Record<string, string>, gps: GPSValue | null) {
    this.tags = tags;
    this.gps = gps;
  }
}

class ImageToolingResult {
  value: Object | null;
  error: string;

  constructor(value: Object | null, error: string = '') {
    this.value = value;
    this.error = error;
  }
}

const MAX_PIXELS: number = 50000000;
const MAX_DIMENSION: number = 16384;
const MAX_IMAGES: number = 16;
let nextCacheID: number = 0;

const EXIF_KEYS: Array<image.PropertyKey> = [
  image.PropertyKey.ORIENTATION,
  image.PropertyKey.IMAGE_DESCRIPTION,
  image.PropertyKey.MAKE,
  image.PropertyKey.MODEL,
  image.PropertyKey.SOFTWARE,
  image.PropertyKey.ARTIST,
  image.PropertyKey.COPYRIGHT,
  image.PropertyKey.DATE_TIME,
  image.PropertyKey.DATE_TIME_ORIGINAL,
  image.PropertyKey.OFFSET_TIME_ORIGINAL,
  image.PropertyKey.USER_COMMENT,
  image.PropertyKey.EXPOSURE_TIME,
  image.PropertyKey.F_NUMBER,
  image.PropertyKey.ISO_SPEED_RATINGS,
  image.PropertyKey.FOCAL_LENGTH,
  image.PropertyKey.LENS_MAKE,
  image.PropertyKey.LENS_MODEL,
];

const GPS_KEYS: Array<image.PropertyKey> = [
  image.PropertyKey.GPS_VERSION_ID,
  image.PropertyKey.GPS_LATITUDE,
  image.PropertyKey.GPS_LATITUDE_REF,
  image.PropertyKey.GPS_LONGITUDE,
  image.PropertyKey.GPS_LONGITUDE_REF,
  image.PropertyKey.GPS_ALTITUDE,
  image.PropertyKey.GPS_ALTITUDE_REF,
  image.PropertyKey.GPS_TIME_STAMP,
  image.PropertyKey.GPS_SATELLITES,
  image.PropertyKey.GPS_STATUS,
  image.PropertyKey.GPS_MEASURE_MODE,
  image.PropertyKey.GPS_DOP,
  image.PropertyKey.GPS_SPEED_REF,
  image.PropertyKey.GPS_SPEED,
  image.PropertyKey.GPS_TRACK_REF,
  image.PropertyKey.GPS_TRACK,
  image.PropertyKey.GPS_IMG_DIRECTION_REF,
  image.PropertyKey.GPS_IMG_DIRECTION,
  image.PropertyKey.GPS_MAP_DATUM,
  image.PropertyKey.GPS_DEST_LATITUDE_REF,
  image.PropertyKey.GPS_DEST_LATITUDE,
  image.PropertyKey.GPS_DEST_LONGITUDE_REF,
  image.PropertyKey.GPS_DEST_LONGITUDE,
  image.PropertyKey.GPS_DEST_BEARING_REF,
  image.PropertyKey.GPS_DEST_BEARING,
  image.PropertyKey.GPS_DEST_DISTANCE_REF,
  image.PropertyKey.GPS_DEST_DISTANCE,
  image.PropertyKey.GPS_PROCESSING_METHOD,
  image.PropertyKey.GPS_AREA_INFORMATION,
  image.PropertyKey.GPS_DATE_STAMP,
  image.PropertyKey.GPS_DIFFERENTIAL,
  image.PropertyKey.GPS_H_POSITIONING_ERROR,
];

/** HarmonyOS native image transforms and EXIF tools. */
export class ImageToolingModule extends LynxModule {
  static readonly NAME: string = 'ImageTooling';

  constructor(context: LynxContext, param?: Object) {
    super(context, param);
  }

  info(uri: string, callback: (resultJSON: string) => void): void {
    this.sourceDescriptor(uri)
      .then((source: SourceDescriptor) => {
        callback(this.valueResult(new InfoValue(source)));
      })
      .catch((error: Error) => {
        callback(this.errorResult(this.errorMessage(
          error, 'ImageTooling failed to read the image info')));
      });
  }

  compress(options: NativeEncodingOptions, callback: (resultJSON: string) => void): void {
    let request: EncodingRequest;
    try {
      request = this.parseEncodingRequest(options, 'compress');
    } catch (error) {
      callback(this.errorResult(this.errorMessage(error)));
      return;
    }
    this.compressRequest(request, 'compressed')
      .then((value: ImageValue) => callback(this.valueResult(value)))
      .catch((error: Error) => callback(this.errorResult(this.errorMessage(
        error, 'ImageTooling failed to compress the image'))));
  }

  crop(options: NativeCropOptions, callback: (resultJSON: string) => void): void {
    let request: CropRequest;
    try {
      request = this.parseCropRequest(options);
    } catch (error) {
      callback(this.errorResult(this.errorMessage(error)));
      return;
    }
    this.cropRequest(request)
      .then((value: ImageValue) => callback(this.valueResult(value)))
      .catch((error: Error) => callback(this.errorResult(this.errorMessage(
        error, 'ImageTooling failed to crop the image'))));
  }

  compose(options: NativeComposeOptions, callback: (resultJSON: string) => void): void {
    let request: ComposeRequest;
    try {
      request = this.parseComposeRequest(options);
    } catch (error) {
      callback(this.errorResult(this.errorMessage(error)));
      return;
    }
    this.composeRequest(request)
      .then((value: ImageValue) => callback(this.valueResult(value)))
      .catch((error: Error) => callback(this.errorResult(this.errorMessage(
        error, 'ImageTooling failed to compose images'))));
  }

  readExif(uri: string, callback: (resultJSON: string) => void): void {
    this.readExifValue(uri)
      .then((value: ExifValue) => callback(this.valueResult(value)))
      .catch((error: Error) => callback(this.errorResult(this.errorMessage(
        error, 'ImageTooling failed to read EXIF metadata'))));
  }

  writeExif(options: NativeExifWriteOptions, callback: (resultJSON: string) => void): void {
    this.writeExifCopy(options)
      .then((value: ImageValue) => callback(this.valueResult(value)))
      .catch((error: Error) => callback(this.errorResult(this.errorMessage(
        error, 'ImageTooling failed to write EXIF metadata'))));
  }

  removeExif(options: NativeEncodingOptions, callback: (resultJSON: string) => void): void {
    let request: RemoveExifRequest;
    try {
      request = this.parseRemoveExifRequest(options);
    } catch (error) {
      callback(this.errorResult(this.errorMessage(error)));
      return;
    }
    this.removeExifRequest(request)
      .then((value: ImageValue) => callback(this.valueResult(value)))
      .catch((error: Error) => callback(this.errorResult(this.errorMessage(
        error, 'ImageTooling failed to remove EXIF metadata'))));
  }

  private async compressRequest(request: EncodingRequest, suffix: string): Promise<ImageValue> {
    const source = await this.sourceDescriptor(request.uri);
    this.validateSource(source);
    const scale = this.fitScale(
      source.displayWidth, source.displayHeight, request.maxWidth, request.maxHeight);
    const width = this.scaled(source.displayWidth, scale);
    const height = this.scaled(source.displayHeight, scale);
    this.validateOutput(width, height);
    const pixelMap = await this.decodeUpright(source, width, height);
    try {
      return await this.writeCacheFile(pixelMap, request.jpeg, request.quality, suffix);
    } finally {
      pixelMap.release();
    }
  }

  private async cropRequest(request: CropRequest): Promise<ImageValue> {
    const source = await this.sourceDescriptor(request.uri);
    this.validateSource(source);
    if (request.x + request.width > source.displayWidth
        || request.y + request.height > source.displayHeight) {
      throw new Error('ImageTooling crop rectangle is outside the oriented image bounds');
    }
    const scale = this.fitScale(
      request.width, request.height, request.maxWidth, request.maxHeight);
    const outputWidth = this.scaled(request.width, scale);
    const outputHeight = this.scaled(request.height, scale);
    this.validateOutput(outputWidth, outputHeight);
    const fullWidth = this.scaled(source.displayWidth, scale);
    const fullHeight = this.scaled(source.displayHeight, scale);
    const pixelMap = await this.decodeUpright(source, fullWidth, fullHeight);
    try {
      const left = Math.min(
        Math.max(0, Math.round(request.x * scale)),
        Math.max(0, fullWidth - outputWidth));
      const top = Math.min(
        Math.max(0, Math.round(request.y * scale)),
        Math.max(0, fullHeight - outputHeight));
      const region: image.Region = {
        x: left,
        y: top,
        size: { width: outputWidth, height: outputHeight },
      };
      await pixelMap.crop(region);
      return await this.writeCacheFile(pixelMap, request.jpeg, request.quality, 'cropped');
    } finally {
      pixelMap.release();
    }
  }

  private async composeRequest(request: ComposeRequest): Promise<ImageValue> {
    const sources: Array<SourceDescriptor> = [];
    let rawWidth = 0;
    let rawHeight = 0;
    for (let index = 0; index < request.layers.length; index += 1) {
      const layer = request.layers[index];
      const source = await this.sourceDescriptor(layer.uri);
      this.validateSource(source);
      sources.push(source);
      if (request.layout === 'horizontal') {
        rawWidth += source.displayWidth;
        rawHeight = Math.max(rawHeight, source.displayHeight);
      } else if (request.layout === 'vertical') {
        rawWidth = Math.max(rawWidth, source.displayWidth);
        rawHeight += source.displayHeight;
      } else {
        rawWidth = Math.max(rawWidth, layer.x + source.displayWidth);
        rawHeight = Math.max(rawHeight, layer.y + source.displayHeight);
      }
    }
    if (request.layout !== 'overlay') {
      const gaps = request.spacing * (request.layers.length - 1);
      if (request.layout === 'horizontal') {
        rawWidth += gaps;
      } else {
        rawHeight += gaps;
      }
    }
    const scale = this.fitScale(rawWidth, rawHeight, request.maxWidth, request.maxHeight);
    const outputWidth = this.scaled(rawWidth, scale);
    const outputHeight = this.scaled(rawHeight, scale);
    this.validateOutput(outputWidth, outputHeight);
    const outputBuffer = new ArrayBuffer(outputWidth * outputHeight * 4);
    const outputPixels = new Uint8Array(outputBuffer);
    if (request.jpeg) {
      for (let offset = 0; offset < outputPixels.length; offset += 4) {
        outputPixels[offset] = 255;
        outputPixels[offset + 1] = 255;
        outputPixels[offset + 2] = 255;
        outputPixels[offset + 3] = 255;
      }
    }
    let cursor = 0;
    for (let index = 0; index < sources.length; index += 1) {
      const source = sources[index];
      const layer = request.layers[index];
      const width = this.scaled(source.displayWidth, scale);
      const height = this.scaled(source.displayHeight, scale);
      const pixelMap = await this.decodeUpright(source, width, height);
      try {
        const pixelInfo = await pixelMap.getImageInfo();
        const buffer = new ArrayBuffer(width * height * 4);
        await pixelMap.readPixelsToBuffer(buffer);
        let left = 0;
        let top = 0;
        if (request.layout === 'horizontal') {
          left = Math.round(cursor * scale);
          cursor += source.displayWidth + request.spacing;
        } else if (request.layout === 'vertical') {
          top = Math.round(cursor * scale);
          cursor += source.displayHeight + request.spacing;
        } else {
          left = Math.round(layer.x * scale);
          top = Math.round(layer.y * scale);
        }
        this.blend(
          outputPixels, outputWidth, outputHeight,
          new Uint8Array(buffer), width, height, left, top, layer.opacity,
          pixelInfo.alphaType === image.AlphaType.PREMUL);
      } finally {
        pixelMap.release();
      }
    }
    const initialization: image.InitializationOptions = {
      size: { width: outputWidth, height: outputHeight },
      pixelFormat: image.PixelMapFormat.RGBA_8888,
      alphaType: request.jpeg ? image.AlphaType.OPAQUE : image.AlphaType.UNPREMUL,
      editable: false,
    };
    const output = await image.createPixelMap(outputBuffer, initialization);
    try {
      return await this.writeCacheFile(
        output, request.jpeg, request.quality, 'composed');
    } finally {
      output.release();
    }
  }

  private blend(
    destination: Uint8Array,
    destinationWidth: number,
    destinationHeight: number,
    source: Uint8Array,
    sourceWidth: number,
    sourceHeight: number,
    left: number,
    top: number,
    opacity: number,
    sourcePremultiplied: boolean,
  ): void {
    for (let y = 0; y < sourceHeight; y += 1) {
      const destinationY = top + y;
      if (destinationY < 0 || destinationY >= destinationHeight) {
        continue;
      }
      for (let x = 0; x < sourceWidth; x += 1) {
        const destinationX = left + x;
        if (destinationX < 0 || destinationX >= destinationWidth) {
          continue;
        }
        const sourceOffset = (y * sourceWidth + x) * 4;
        const destinationOffset = (destinationY * destinationWidth + destinationX) * 4;
        const pixelAlpha = source[sourceOffset + 3] / 255.0;
        const sourceAlpha = pixelAlpha * opacity;
        if (sourceAlpha <= 0) {
          continue;
        }
        const destinationAlpha = destination[destinationOffset + 3] / 255.0;
        const outputAlpha = sourceAlpha + destinationAlpha * (1.0 - sourceAlpha);
        if (outputAlpha <= 0) {
          continue;
        }
        for (let component = 0; component < 3; component += 1) {
          const sourceValue = sourcePremultiplied
            ? Math.min(255, source[sourceOffset + component] / pixelAlpha)
            : source[sourceOffset + component];
          const destinationValue = destination[destinationOffset + component];
          destination[destinationOffset + component] = Math.round(
            (sourceValue * sourceAlpha
              + destinationValue * destinationAlpha * (1.0 - sourceAlpha)) / outputAlpha);
        }
        destination[destinationOffset + 3] = Math.round(outputAlpha * 255.0);
      }
    }
  }

  private async sourceDescriptor(uri: string): Promise<SourceDescriptor> {
    const normalized = this.requireURI(uri);
    let source: image.ImageSource;
    try {
      source = image.createImageSource(normalized);
    } catch (error) {
      throw new Error(this.errorMessage(error, 'ImageTooling cannot open the image URI'));
    }
    try {
      const info = await source.getImageInfo();
      const orientation = await this.safeOrientation(source);
      return new SourceDescriptor(
        normalized,
        info.size.width,
        info.size.height,
        orientation,
        info.mimeType.length > 0 ? info.mimeType : null,
        this.sizeOf(normalized),
      );
    } finally {
      source.release();
    }
  }

  private async decodeUpright(
    descriptor: SourceDescriptor,
    targetWidth: number,
    targetHeight: number,
  ): Promise<image.PixelMap> {
    const source = image.createImageSource(descriptor.uri);
    const quarterTurn = descriptor.orientation === 'Left-top'
      || descriptor.orientation === 'Right-top'
      || descriptor.orientation === 'Right-bottom'
      || descriptor.orientation === 'Left-bottom';
    const options: image.DecodingOptions = {
      desiredSize: {
        width: quarterTurn ? targetHeight : targetWidth,
        height: quarterTurn ? targetWidth : targetHeight,
      },
      desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
      rotate: this.rotation(descriptor.orientation),
      editable: true,
    };
    let pixelMap: image.PixelMap;
    try {
      pixelMap = await source.createPixelMap(options);
    } finally {
      source.release();
    }
    if (descriptor.orientation === 'Top-right') {
      await pixelMap.flip(true, false);
    } else if (descriptor.orientation === 'Bottom-left') {
      await pixelMap.flip(false, true);
    } else if (descriptor.orientation === 'Left-top'
        || descriptor.orientation === 'Right-bottom') {
      await pixelMap.flip(true, false);
    }
    const info = await pixelMap.getImageInfo();
    if (info.size.width !== targetWidth || info.size.height !== targetHeight) {
      await pixelMap.scale(
        targetWidth / info.size.width,
        targetHeight / info.size.height,
        image.AntiAliasingLevel.MEDIUM,
      );
    }
    return pixelMap;
  }

  private rotation(orientation: string): number {
    if (orientation === 'Right-top' || orientation === 'Left-top') {
      return 90;
    }
    if (orientation === 'Bottom-right') {
      return 180;
    }
    if (orientation === 'Left-bottom' || orientation === 'Right-bottom') {
      return 270;
    }
    return 0;
  }

  private async safeOrientation(source: image.ImageSource): Promise<string> {
    try {
      return await source.getImageProperty(image.PropertyKey.ORIENTATION);
    } catch (_error) {
      return 'Top-left';
    }
  }

  private async writeCacheFile(
    pixelMap: image.PixelMap,
    jpeg: boolean,
    quality: number,
    suffix: string,
  ): Promise<ImageValue> {
    let output = pixelMap;
    if (jpeg) {
      output = await this.flattenOntoWhite(pixelMap);
    }
    const info = await output.getImageInfo();
    const extension = jpeg ? 'jpg' : 'png';
    const destination = this.cacheDestination(suffix, extension);
    const file: fs.File = fs.openSync(
      destination,
      fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC,
    );
    try {
      const packer = image.createImagePacker();
      const packingOptions: image.PackingOption = {
        format: jpeg ? 'image/jpeg' : 'image/png',
        quality,
      };
      await packer.packToFile(output, file.fd, packingOptions);
    } finally {
      fs.closeSync(file);
      if (output !== pixelMap) {
        output.release();
      }
    }
    const stat = fs.statSync(destination);
    return new ImageValue(
      `file://${destination}`, info.size.width, info.size.height, stat.size);
  }

  private async flattenOntoWhite(pixelMap: image.PixelMap): Promise<image.PixelMap> {
    const info = await pixelMap.getImageInfo();
    if (info.alphaType === image.AlphaType.OPAQUE) {
      return pixelMap;
    }
    const width = info.size.width;
    const height = info.size.height;
    const buffer = new ArrayBuffer(width * height * 4);
    await pixelMap.readPixelsToBuffer(buffer);
    const pixels = new Uint8Array(buffer);
    const premultiplied = info.alphaType === image.AlphaType.PREMUL;
    for (let index = 0; index < width * height; index += 1) {
      const offset = index * 4;
      const alpha = pixels[offset + 3];
      if (alpha === 255) {
        continue;
      }
      const inverse = 255 - alpha;
      if (premultiplied) {
        pixels[offset] = Math.min(255, pixels[offset] + inverse);
        pixels[offset + 1] = Math.min(255, pixels[offset + 1] + inverse);
        pixels[offset + 2] = Math.min(255, pixels[offset + 2] + inverse);
      } else {
        pixels[offset] = Math.round((pixels[offset] * alpha + 255 * inverse) / 255);
        pixels[offset + 1] = Math.round(
          (pixels[offset + 1] * alpha + 255 * inverse) / 255);
        pixels[offset + 2] = Math.round(
          (pixels[offset + 2] * alpha + 255 * inverse) / 255);
      }
      pixels[offset + 3] = 255;
    }
    const initialization: image.InitializationOptions = {
      size: { width, height },
      pixelFormat: image.PixelMapFormat.RGBA_8888,
      alphaType: image.AlphaType.OPAQUE,
      editable: false,
    };
    return image.createPixelMap(buffer, initialization);
  }

  private async readExifValue(uri: string): Promise<ExifValue> {
    const normalized = this.requireURI(uri);
    const source = image.createImageSource(normalized);
    try {
      const keys = EXIF_KEYS.concat(GPS_KEYS);
      const properties = await source.getImageProperties(keys);
      const tags: Record<string, string> = {};
      for (let index = 0; index < EXIF_KEYS.length; index += 1) {
        const key = EXIF_KEYS[index];
        const value = properties[key];
        if (value !== null && value.length > 0) {
          tags[key] = key === image.PropertyKey.ORIENTATION
            ? this.canonicalOrientation(value)
            : value;
        }
      }
      const latitudeValue = properties[image.PropertyKey.GPS_LATITUDE];
      const longitudeValue = properties[image.PropertyKey.GPS_LONGITUDE];
      let gps: GPSValue | null = null;
      if (latitudeValue !== null && longitudeValue !== null) {
        let latitude = this.parseCoordinate(latitudeValue);
        let longitude = this.parseCoordinate(longitudeValue);
        if (properties[image.PropertyKey.GPS_LATITUDE_REF] === 'S') {
          latitude *= -1;
        }
        if (properties[image.PropertyKey.GPS_LONGITUDE_REF] === 'W') {
          longitude *= -1;
        }
        const altitudeValue = properties[image.PropertyKey.GPS_ALTITUDE];
        if (altitudeValue !== null) {
          let altitude = this.parseRational(altitudeValue);
          if (properties[image.PropertyKey.GPS_ALTITUDE_REF] === '1') {
            altitude *= -1;
          }
          gps = new GPSValue(latitude, longitude, altitude);
        } else {
          gps = new GPSValue(latitude, longitude);
        }
      }
      return new ExifValue(tags, gps);
    } finally {
      source.release();
    }
  }

  private async writeExifCopy(options: NativeExifWriteOptions): Promise<ImageValue> {
    if (options === undefined || options === null) {
      throw new Error('ImageTooling writeExif requires options');
    }
    const uri = this.requireURI(options.uri);
    if (!uri.startsWith('file://')) {
      throw new Error('ImageTooling EXIF writing requires a file:// URI on HarmonyOS');
    }
    const descriptor = await this.sourceDescriptor(uri);
    const extension = this.sourceExtension(descriptor);
    const destination = this.cacheDestination('exif', extension);
    fs.copyFileSync(uri.substring('file://'.length), destination);
    const destinationURI = `file://${destination}`;
    const source = image.createImageSource(destinationURI);
    try {
      const records = {} as Record<image.PropertyKey, string | null>;
      if (options.tags !== undefined && options.tags !== null) {
        const names = Object.keys(options.tags);
        for (let index = 0; index < names.length; index += 1) {
          const name = names[index];
          const key = this.propertyKey(name);
          records[key] = options.tags[name];
        }
      }
      if (options.gps !== undefined) {
        if (options.gps === null) {
          for (let index = 0; index < GPS_KEYS.length; index += 1) {
            records[GPS_KEYS[index]] = null;
          }
        } else {
          const gps = options.gps;
          if (gps.latitude === undefined || gps.longitude === undefined) {
            throw new Error('Invalid ImageTooling GPS update');
          }
          records[image.PropertyKey.GPS_LATITUDE] = this.coordinateString(gps.latitude);
          records[image.PropertyKey.GPS_LATITUDE_REF] = gps.latitude < 0 ? 'S' : 'N';
          records[image.PropertyKey.GPS_LONGITUDE] = this.coordinateString(gps.longitude);
          records[image.PropertyKey.GPS_LONGITUDE_REF] = gps.longitude < 0 ? 'W' : 'E';
          if (gps.altitude === null) {
            records[image.PropertyKey.GPS_ALTITUDE] = null;
            records[image.PropertyKey.GPS_ALTITUDE_REF] = null;
          } else if (gps.altitude !== undefined) {
            records[image.PropertyKey.GPS_ALTITUDE] = this.rational(Math.abs(gps.altitude));
            records[image.PropertyKey.GPS_ALTITUDE_REF] = gps.altitude < 0 ? '1' : '0';
          }
        }
      }
      await source.modifyImageProperties(records);
    } finally {
      source.release();
    }
    const result = await this.sourceDescriptor(destinationURI);
    const stat = fs.statSync(destination);
    return new ImageValue(
      destinationURI, result.displayWidth, result.displayHeight, stat.size);
  }

  private async removeExifRequest(request: RemoveExifRequest): Promise<ImageValue> {
    const source = await this.sourceDescriptor(request.uri);
    this.validateSource(source);
    if (!request.formatSpecified) {
      request.jpeg = source.mimeType !== 'image/png';
    }
    this.validateOutput(source.displayWidth, source.displayHeight);
    const pixelMap = await this.decodeUpright(
      source, source.displayWidth, source.displayHeight);
    try {
      return await this.writeCacheFile(
        pixelMap, request.jpeg, request.quality, 'exif-removed');
    } finally {
      pixelMap.release();
    }
  }

  private propertyKey(name: string): image.PropertyKey {
    switch (name) {
      case 'Orientation': return image.PropertyKey.ORIENTATION;
      case 'ImageDescription': return image.PropertyKey.IMAGE_DESCRIPTION;
      case 'Make': return image.PropertyKey.MAKE;
      case 'Model': return image.PropertyKey.MODEL;
      case 'Software': return image.PropertyKey.SOFTWARE;
      case 'Artist': return image.PropertyKey.ARTIST;
      case 'Copyright': return image.PropertyKey.COPYRIGHT;
      case 'DateTime': return image.PropertyKey.DATE_TIME;
      case 'DateTimeOriginal': return image.PropertyKey.DATE_TIME_ORIGINAL;
      case 'OffsetTimeOriginal': return image.PropertyKey.OFFSET_TIME_ORIGINAL;
      case 'UserComment': return image.PropertyKey.USER_COMMENT;
      case 'ExposureTime': return image.PropertyKey.EXPOSURE_TIME;
      case 'FNumber': return image.PropertyKey.F_NUMBER;
      case 'ISOSpeedRatings': return image.PropertyKey.ISO_SPEED_RATINGS;
      case 'FocalLength': return image.PropertyKey.FOCAL_LENGTH;
      case 'LensMake': return image.PropertyKey.LENS_MAKE;
      case 'LensModel': return image.PropertyKey.LENS_MODEL;
      default: throw new Error(`Unsupported ImageTooling EXIF tag: ${name}`);
    }
  }

  private parseCoordinate(value: string): number {
    const parts = value.split(',');
    if (parts.length >= 3) {
      return this.parseRational(parts[0])
        + this.parseRational(parts[1]) / 60.0
        + this.parseRational(parts[2]) / 3600.0;
    }
    const decimal = Number.parseFloat(value);
    if (!Number.isFinite(decimal)) {
      throw new Error('ImageTooling found invalid EXIF GPS coordinates');
    }
    return Math.abs(decimal);
  }

  private parseRational(value: string): number {
    const parts = value.trim().split('/');
    const numerator = Number.parseFloat(parts[0]);
    const denominator = parts.length > 1 ? Number.parseFloat(parts[1]) : 1;
    if (!Number.isFinite(numerator) || !Number.isFinite(denominator) || denominator === 0) {
      throw new Error('ImageTooling found invalid EXIF rational data');
    }
    return numerator / denominator;
  }

  private coordinateString(value: number): string {
    const absolute = Math.abs(value);
    const degrees = Math.floor(absolute);
    const minutesValue = (absolute - degrees) * 60.0;
    const minutes = Math.floor(minutesValue);
    const seconds = (minutesValue - minutes) * 60.0;
    return `${degrees}/1,${minutes}/1,${Math.round(seconds * 1000000)}/1000000`;
  }

  private rational(value: number): string {
    return `${Math.round(value * 1000)}/1000`;
  }

  private canonicalOrientation(value: string): string {
    switch (value) {
      case 'Top-left': return '1';
      case 'Top-right': return '2';
      case 'Bottom-right': return '3';
      case 'Bottom-left': return '4';
      case 'Left-top': return '5';
      case 'Right-top': return '6';
      case 'Right-bottom': return '7';
      case 'Left-bottom': return '8';
      default: return value;
    }
  }

  private parseEncodingRequest(
    options: NativeEncodingOptions,
    action: string,
  ): EncodingRequest {
    if (options === undefined || options === null) {
      throw new Error(`ImageTooling ${action} requires options`);
    }
    const request = new EncodingRequest();
    request.uri = this.requireURI(options.uri);
    request.maxWidth = this.optionalPositive(options.maxWidth);
    request.maxHeight = this.optionalPositive(options.maxHeight);
    request.quality = this.positive(options.quality, 80);
    request.jpeg = this.parseJPEG(options.format, true);
    return request;
  }

  private parseCropRequest(options: NativeCropOptions): CropRequest {
    if (options === undefined || options === null) {
      throw new Error('ImageTooling crop requires options');
    }
    const request = new CropRequest();
    request.uri = this.requireURI(options.uri);
    request.x = this.nonNegative(options.x, 0);
    request.y = this.nonNegative(options.y, 0);
    request.width = this.positive(options.width, 0);
    request.height = this.positive(options.height, 0);
    request.maxWidth = this.optionalPositive(options.maxWidth);
    request.maxHeight = this.optionalPositive(options.maxHeight);
    request.quality = this.positive(options.quality, 80);
    request.jpeg = this.parseJPEG(options.format, true);
    return request;
  }

  private parseComposeRequest(options: NativeComposeOptions): ComposeRequest {
    if (options === undefined || options === null) {
      throw new Error('ImageTooling compose requires options');
    }
    if (options.images === undefined || options.images === null
        || options.images.length < 1 || options.images.length > MAX_IMAGES) {
      throw new Error(`ImageTooling compose requires 1-${MAX_IMAGES} images`);
    }
    if (options.layout !== 'horizontal' && options.layout !== 'vertical'
        && options.layout !== 'overlay') {
      throw new Error('Invalid ImageTooling compose layout');
    }
    const request = new ComposeRequest();
    request.layout = options.layout;
    request.spacing = this.nonNegative(options.spacing, 0);
    request.maxWidth = this.optionalPositive(options.maxWidth);
    request.maxHeight = this.optionalPositive(options.maxHeight);
    request.quality = this.positive(options.quality, 80);
    request.jpeg = this.parseJPEG(options.format, true);
    for (let index = 0; index < options.images.length; index += 1) {
      const raw = options.images[index];
      const layer = new ComposeLayer();
      layer.uri = this.requireURI(raw.uri);
      layer.x = this.nonNegative(raw.x, 0);
      layer.y = this.nonNegative(raw.y, 0);
      layer.opacity = raw.opacity === undefined ? 1.0 : raw.opacity;
      if (!Number.isFinite(layer.opacity) || layer.opacity < 0 || layer.opacity > 1) {
        throw new Error('Invalid ImageTooling layer opacity');
      }
      request.layers.push(layer);
    }
    return request;
  }

  private parseRemoveExifRequest(options: NativeEncodingOptions): RemoveExifRequest {
    if (options === undefined || options === null) {
      throw new Error('ImageTooling removeExif requires options');
    }
    const request = new RemoveExifRequest();
    request.uri = this.requireURI(options.uri);
    request.quality = this.positive(options.quality, 100);
    request.formatSpecified = options.format !== undefined && options.format !== null;
    request.jpeg = request.formatSpecified ? this.parseJPEG(options.format, true) : true;
    return request;
  }

  private requireURI(value: string | undefined): string {
    if (value === undefined || value === null || value.trim().length === 0) {
      throw new Error('ImageTooling requires a non-empty image URI');
    }
    return value.trim();
  }

  private positive(value: number | null | undefined, fallback: number): number {
    const number = value === undefined || value === null ? fallback : value;
    if (!Number.isInteger(number) || number < 1) {
      throw new Error('ImageTooling expected a positive integer');
    }
    return number;
  }

  private optionalPositive(value: number | null | undefined): number {
    if (value === undefined || value === null) {
      return 0;
    }
    return this.positive(value, 0);
  }

  private nonNegative(value: number | null | undefined, fallback: number): number {
    const number = value === undefined || value === null ? fallback : value;
    if (!Number.isInteger(number) || number < 0) {
      throw new Error('ImageTooling expected a non-negative integer');
    }
    return number;
  }

  private parseJPEG(value: string | null | undefined, fallback: boolean): boolean {
    if (value === undefined || value === null) {
      return fallback;
    }
    if (value === 'jpeg') {
      return true;
    }
    if (value === 'png') {
      return false;
    }
    throw new Error(`Invalid ImageTooling format: ${value}`);
  }

  private fitScale(
    width: number,
    height: number,
    maxWidth: number,
    maxHeight: number,
  ): number {
    let scale = 1.0;
    if (maxWidth > 0 && width > maxWidth) {
      scale = Math.min(scale, maxWidth / width);
    }
    if (maxHeight > 0 && height > maxHeight) {
      scale = Math.min(scale, maxHeight / height);
    }
    return scale;
  }

  private scaled(value: number, scale: number): number {
    return Math.max(1, Math.round(value * scale));
  }

  private validateSource(source: SourceDescriptor): void {
    if (source.rawWidth < 1 || source.rawHeight < 1) {
      throw new Error('ImageTooling cannot decode the image');
    }
    if (source.rawWidth * source.rawHeight > MAX_PIXELS) {
      throw new Error('ImageTooling image is larger than 50 MP');
    }
  }

  private validateOutput(width: number, height: number): void {
    if (width < 1 || height < 1 || width > MAX_DIMENSION || height > MAX_DIMENSION) {
      throw new Error(`ImageTooling output dimensions must not exceed ${MAX_DIMENSION}`);
    }
    if (width * height > MAX_PIXELS) {
      throw new Error('ImageTooling output is larger than 50 MP');
    }
  }

  private cacheDestination(suffix: string, extension: string): string {
    const abilityContext = this.abilityContext();
    if (abilityContext === undefined) {
      throw new Error('ImageTooling has no UIAbilityContext');
    }
    const directory = `${abilityContext.cacheDir}/LynxImages`;
    if (!fs.accessSync(directory)) {
      fs.mkdirSync(directory, true);
    }
    nextCacheID += 1;
    return `${directory}/${Date.now()}-${nextCacheID}-${suffix}.${extension}`;
  }

  private sourceExtension(source: SourceDescriptor): string {
    if (source.mimeType === 'image/png') return 'png';
    if (source.mimeType === 'image/webp') return 'webp';
    if (source.mimeType === 'image/heic' || source.mimeType === 'image/heif') return 'heic';
    return 'jpg';
  }

  private sizeOf(uri: string): number | null {
    try {
      if (uri.startsWith('file://')) {
        return fs.statSync(uri.substring('file://'.length)).size;
      }
    } catch (_error) {
    }
    return null;
  }

  private abilityContext(): common.UIAbilityContext | undefined {
    const hostContext = this.context.getUIOwner()?.uiContext.getHostContext();
    return hostContext as common.UIAbilityContext | undefined;
  }

  private valueResult(value: Object): string {
    return JSON.stringify(new ImageToolingResult(value));
  }

  private errorResult(message: string): string {
    return JSON.stringify(new ImageToolingResult(null, message));
  }

  private errorMessage(error: Object, fallback: string = ''): string {
    const typed = error as Error;
    if (typed.message !== undefined && typed.message.length > 0) {
      return typed.message;
    }
    return fallback.length > 0 ? fallback : 'ImageTooling failed';
  }
}
