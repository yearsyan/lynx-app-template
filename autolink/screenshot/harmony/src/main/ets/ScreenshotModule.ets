import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { LynxContext, LynxModule } from '@lynx/lynx';

/** Options forwarded by the shared TypeScript bridge. */
export interface NativeScreenshotOptions {
  idSelector?: string;
  format?: string;
  quality?: number;
  fileName?: string;
}

class ScreenshotRequest {
  idSelector: string = '';
  jpeg: boolean = false;
  quality: number = 80;
  fileName: string = '';
}

class ScreenshotValue {
  uri: string;
  width: number;
  height: number;

  constructor(uri: string, width: number, height: number) {
    this.uri = uri;
    this.width = width;
    this.height = height;
  }
}

class ScreenshotResult {
  value: ScreenshotValue | null;
  error: string;

  constructor(value: ScreenshotValue | null, error: string = '') {
    this.value = value;
    this.error = error;
  }
}

/** Lynx component and window snapshots exported to Lynx as Screenshot. */
export class ScreenshotModule extends LynxModule {
  static readonly NAME: string = 'Screenshot';
  private static readonly MAX_FILE_NAME_LENGTH: number = 120;
  private static nextCacheID: number = 0;

  constructor(context: LynxContext, param?: Object) {
    super(context, param);
  }

  capture(options: NativeScreenshotOptions, callback: (resultJSON: string) => void): void {
    let request: ScreenshotRequest;
    try {
      request = this.parseRequest(options);
    } catch (error) {
      callback(this.errorResult(this.errorMessage(error)));
      return;
    }
    this.context.getComponentSnapshot(request.idSelector)
      .then((pixelMap: image.PixelMap) => {
        this.encodeAndSave(pixelMap, request, callback);
      })
      .catch((error: Error) => {
        const target = request.idSelector.length > 0 ? request.idSelector : 'LynxView';
        callback(this.errorResult(this.errorMessage(
          error,
          `Unable to capture ${target}`,
        )));
      });
  }

  capturePage(options: NativeScreenshotOptions, callback: (resultJSON: string) => void): void {
    let request: ScreenshotRequest;
    try {
      request = this.parseRequest(options);
    } catch (error) {
      callback(this.errorResult(this.errorMessage(error)));
      return;
    }
    if (request.idSelector.length > 0) {
      callback(this.errorResult('Screenshot capturePage does not support idSelector'));
      return;
    }
    const currentWindow = this.context.getCurrentWindow();
    if (currentWindow === undefined) {
      callback(this.errorResult('Screenshot has no Lynx window'));
      return;
    }
    currentWindow
      .then((hostWindow) => hostWindow.snapshot())
      .then((pixelMap: image.PixelMap) => {
        this.encodeAndSave(pixelMap, request, callback);
      })
      .catch((error: Error) => {
        callback(this.errorResult(this.errorMessage(error, 'Unable to capture the app window')));
      });
  }

  private encodeAndSave(
    pixelMap: image.PixelMap,
    request: ScreenshotRequest,
    callback: (resultJSON: string) => void,
  ): void {
    const packer = image.createImagePacker();
    const options: image.PackingOption = {
      format: request.jpeg ? 'image/jpeg' : 'image/png',
      quality: request.quality,
    };
    packer.packing(pixelMap, options)
      .then((buffer: ArrayBuffer) => {
        packer.release();
        this.finishCapture(pixelMap, buffer, request, callback);
      })
      .catch((error: Error) => {
        packer.release();
        pixelMap.release();
        callback(this.errorResult(this.errorMessage(error, 'Unable to encode the screenshot')));
      });
  }

  private finishCapture(
    pixelMap: image.PixelMap,
    buffer: ArrayBuffer,
    request: ScreenshotRequest,
    callback: (resultJSON: string) => void,
  ): void {
    pixelMap.getImageInfo()
      .then((info: image.ImageInfo) => {
        pixelMap.release();
        try {
          const uri = this.writeCacheFile(buffer, request);
          callback(JSON.stringify(new ScreenshotResult(
            new ScreenshotValue(uri, info.size.width, info.size.height),
          )));
        } catch (error) {
          callback(this.errorResult(this.errorMessage(error)));
        }
      })
      .catch((error: Error) => {
        pixelMap.release();
        callback(this.errorResult(this.errorMessage(error, 'Unable to measure the screenshot')));
      });
  }

  private parseRequest(options: NativeScreenshotOptions): ScreenshotRequest {
    const request = new ScreenshotRequest();
    if (options.idSelector !== undefined && options.idSelector !== null) {
      const idSelector = options.idSelector.trim();
      if (idSelector.length > 128) {
        throw new Error('Screenshot idSelector is longer than 128 characters');
      }
      request.idSelector = idSelector;
    }
    const format = options.format ?? 'png';
    if (format !== 'png' && format !== 'jpeg') {
      throw new Error(`Invalid screenshot format: ${format}`);
    }
    request.jpeg = format === 'jpeg';
    const quality = options.quality ?? 80;
    if (!Number.isInteger(quality) || quality < 1 || quality > 100) {
      throw new Error('Screenshot quality must be between 1 and 100');
    }
    request.quality = quality;
    if (options.fileName !== undefined && options.fileName !== null) {
      request.fileName = this.sanitizeName(options.fileName);
    }
    return request;
  }

  private writeCacheFile(buffer: ArrayBuffer, request: ScreenshotRequest): string {
    const abilityContext = this.abilityContext();
    if (abilityContext === undefined) {
      throw new Error('Screenshot has no UIAbilityContext');
    }
    const directory = `${abilityContext.cacheDir}/LynxImages`;
    if (!fs.accessSync(directory)) {
      fs.mkdirSync(directory, true);
    }
    ScreenshotModule.nextCacheID += 1;
    const name = request.fileName.length > 0 ? request.fileName : 'screenshot';
    const extension = request.jpeg ? 'jpg' : 'png';
    const destination =
      `${directory}/${Date.now()}-${ScreenshotModule.nextCacheID}-${name}.${extension}`;
    const file: fs.File = fs.openSync(
      destination,
      fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC,
    );
    try {
      fs.writeSync(file.fd, buffer);
    } finally {
      fs.closeSync(file);
    }
    return `file://${destination}`;
  }

  private abilityContext(): common.UIAbilityContext | undefined {
    const hostContext = this.context.getUIOwner()?.uiContext.getHostContext();
    return hostContext as common.UIAbilityContext | undefined;
  }

  private sanitizeName(name: string): string {
    const sanitized = name
      .replace(new RegExp('[\\\\/:*?"<>|\\x00-\\x1F]', 'g'), '_')
      .trim();
    if (sanitized.length === 0) {
      return '';
    }
    return sanitized.length > ScreenshotModule.MAX_FILE_NAME_LENGTH
      ? sanitized.substring(sanitized.length - ScreenshotModule.MAX_FILE_NAME_LENGTH)
      : sanitized;
  }

  private errorResult(message: string): string {
    return JSON.stringify(new ScreenshotResult(null, message));
  }

  private errorMessage(error: Object, fallback: string = ''): string {
    const typed = error as Error;
    if (typed.message !== undefined && typed.message.length > 0) {
      return typed.message;
    }
    return fallback.length > 0 ? fallback : 'Screenshot capture failed';
  }
}
