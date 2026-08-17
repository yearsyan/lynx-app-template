import { UIContext } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { LynxContext, LynxModule } from '@lynx/lynx';

/**
 * Component id of the page root container in pages/Index.ets. The whole
 * page is captured through componentSnapshot with this id.
 */
export const SCREENSHOT_PAGE_ROOT_ID: string = 'lynx-page-root';

/**
 * Component id of the LynxBundlePage container that wraps the LynxView.
 * Unique per route instance so stacked navigation pages resolve to the
 * right component.
 */
export function screenshotViewContainerId(nativeBackID: string): string {
  return `lynx-view-${nativeBackID}`;
}

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

/** Carries the page-scoped handles the module needs to capture components. */
export class NativeScreenshotRegistration {
  readonly uiContext: UIContext;
  readonly context: common.UIAbilityContext;
  readonly lynxViewContainerId: string;
  readonly pageRootId: string;

  constructor(
    uiContext: UIContext,
    context: common.UIAbilityContext,
    lynxViewContainerId: string,
    pageRootId: string,
  ) {
    this.uiContext = uiContext;
    this.context = context;
    this.lynxViewContainerId = lynxViewContainerId;
    this.pageRootId = pageRootId;
  }
}

/**
 * View snapshots encoded into the app cache directory, exported to Lynx as
 * Screenshot. The HarmonyOS LynxContext does not expose its view and the
 * Lynx component tree is CAPI-rendered, so both entry points capture host
 * containers with componentSnapshot; element-level idSelector capture is
 * rejected because there is no element-to-component mapping.
 */
export class ScreenshotModule extends LynxModule {
  static readonly NAME: string = 'Screenshot';
  private static readonly MAX_FILE_NAME_LENGTH: number = 120;
  private static nextCacheID: number = 0;

  private readonly registration: NativeScreenshotRegistration | undefined;

  constructor(context: LynxContext, param?: Object) {
    super(context, param);
    this.registration = param as NativeScreenshotRegistration | undefined;
  }

  capture(options: NativeScreenshotOptions, callback: (resultJSON: string) => void): void {
    const registration = this.registration;
    if (registration === undefined) {
      callback(this.errorResult('Screenshot has no page registration'));
      return;
    }
    let request: ScreenshotRequest;
    try {
      request = this.parseRequest(options);
    } catch (error) {
      callback(this.errorResult(this.errorMessage(error)));
      return;
    }
    if (request.idSelector.length > 0) {
      callback(this.errorResult(
        'Screenshot idSelector is not supported on HarmonyOS'));
      return;
    }
    this.captureComponent(registration.lynxViewContainerId, request, callback);
  }

  capturePage(options: NativeScreenshotOptions, callback: (resultJSON: string) => void): void {
    const registration = this.registration;
    if (registration === undefined) {
      callback(this.errorResult('Screenshot has no page registration'));
      return;
    }
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
    this.captureComponent(registration.pageRootId, request, callback);
  }

  private requireRegistration(): NativeScreenshotRegistration {
    if (this.registration === undefined) {
      throw new Error('Screenshot has no page registration');
    }
    return this.registration;
  }

  private captureComponent(
    componentId: string,
    request: ScreenshotRequest,
    callback: (resultJSON: string) => void,
  ): void {
    const registration = this.requireRegistration();
    registration.uiContext.getComponentSnapshot().get(componentId)
      .then((pixelMap: image.PixelMap) => {
        this.encodeAndSave(pixelMap, request, callback);
      })
      .catch((error: Error) => {
        callback(this.errorResult(this.errorMessage(
          error,
          `Unable to capture the component ${componentId}`)));
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
      // PNG ignores the quality field; PackingOption requires it.
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
          const uri: string = this.writeCacheFile(buffer, request);
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
    // The bridge may deliver JSON null as well as undefined for absent fields.
    if (options.idSelector !== undefined && options.idSelector !== null) {
      const idSelector: string = options.idSelector.trim();
      if (idSelector.length > 128) {
        throw new Error('Screenshot idSelector is longer than 128 characters');
      }
      request.idSelector = idSelector;
    }
    const format: string = options.format ?? 'png';
    if (format !== 'png' && format !== 'jpeg') {
      throw new Error(`Invalid screenshot format: ${format}`);
    }
    request.jpeg = format === 'jpeg';
    const quality: number = options.quality ?? 80;
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
    const registration = this.requireRegistration();
    const directory: string = `${registration.context.cacheDir}/LynxImages`;
    if (!fs.accessSync(directory)) {
      fs.mkdirSync(directory, true);
    }
    ScreenshotModule.nextCacheID += 1;
    const name: string = request.fileName.length > 0 ? request.fileName : 'screenshot';
    const extension: string = request.jpeg ? 'jpg' : 'png';
    const destination: string =
      `${directory}/${Date.now()}-${ScreenshotModule.nextCacheID}-${name}.${extension}`;
    const file: fs.File = fs.openSync(
      destination,
      fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(file.fd, buffer);
    } finally {
      fs.closeSync(file);
    }
    return `file://${destination}`;
  }

  private sanitizeName(name: string): string {
    const sanitized: string = name
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
    const typed: Error = error as Error;
    if (typed.message !== undefined && typed.message.length > 0) {
      return typed.message;
    }
    return fallback.length > 0 ? fallback : 'Screenshot capture failed';
  }
}
