import { common } from '@kit.AbilityKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { LynxContext, LynxModule } from '@lynx/lynx';

class NativePickerResult {
  uris: Array<string>;
  error: string;

  constructor(uris: Array<string> = [], error: string = '') {
    this.uris = uris;
    this.error = error;
  }
}

/** HarmonyOS album utilities exported to Lynx as AlbumUtils. */
export class AlbumUtilsModule extends LynxModule {
  static readonly NAME: string = 'AlbumUtils';
  private readonly abilityContext: common.UIAbilityContext;
  private isPicking: boolean = false;

  constructor(context: LynxContext, param?: Object) {
    super(context, param);
    this.abilityContext = getContext(this) as common.UIAbilityContext;
  }

  pick(maxSelection: number, callback: (resultJSON: string) => void): void {
    if (!Number.isInteger(maxSelection) || maxSelection < 1 || maxSelection > 50) {
      callback(this.encodeError('Image picker maxSelection must be between 1 and 50'));
      return;
    }
    if (this.isPicking) {
      callback(this.encodeError('Another image picker request is already active'));
      return;
    }
    this.isPicking = true;

    const options = new photoAccessHelper.PhotoSelectOptions();
    options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
    options.maxSelectNumber = maxSelection;
    try {
      const picker = new photoAccessHelper.PhotoViewPicker();
      picker.select(options).then((result: photoAccessHelper.PhotoSelectResult) => {
        this.isPicking = false;
        callback(this.encodeURIs(result.photoUris.slice(0, maxSelection)));
      }).catch((error: Error) => {
        this.isPicking = false;
        if (this.isCancellation(error)) {
          callback(this.encodeURIs([]));
          return;
        }
        callback(this.encodeError(this.errorMessage(error, 'Unable to select images')));
      });
    } catch (error) {
      this.isPicking = false;
      const pickerError = error as Error;
      callback(this.encodeError(this.errorMessage(pickerError, 'Unable to open the image picker')));
    }
  }

  async saveToAlbum(uri: string, callback: (error: string) => void): Promise<void> {
    const imageURI: string = uri.trim();
    if (imageURI.length === 0) {
      callback('Image URI must not be empty');
      return;
    }
    try {
      const helper: photoAccessHelper.PhotoAccessHelper =
        photoAccessHelper.getPhotoAccessHelper(this.abilityContext);
      const request: photoAccessHelper.MediaAssetChangeRequest =
        photoAccessHelper.MediaAssetChangeRequest.createAssetRequest(
          this.abilityContext,
          photoAccessHelper.PhotoType.IMAGE,
          this.imageExtension(imageURI),
        );
      request.addResource(photoAccessHelper.ResourceType.IMAGE_RESOURCE, imageURI);
      await helper.applyChanges(request);
      callback('');
    } catch (error) {
      callback(this.errorMessage(error as Error, 'Unable to save the image to the album'));
    }
  }

  private imageExtension(uri: string): string {
    const name: string = this.fileName(uri);
    const extensionIndex: number = name.lastIndexOf('.');
    if (extensionIndex < 0 || extensionIndex === name.length - 1) {
      return 'jpg';
    }
    const extension: string = name.substring(extensionIndex + 1).toLowerCase();
    switch (extension) {
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
      case 'heic':
      case 'bmp':
        return extension;
      default:
        return 'jpg';
    }
  }

  private fileName(uri: string): string {
    let value: string = uri;
    const queryIndex: number = value.indexOf('?');
    if (queryIndex >= 0) {
      value = value.substring(0, queryIndex);
    }
    const separator: number = value.lastIndexOf('/');
    return separator >= 0 ? value.substring(separator + 1) : value;
  }

  private encodeURIs(uris: Array<string>): string {
    return JSON.stringify(new NativePickerResult(uris));
  }

  private encodeError(message: string): string {
    return JSON.stringify(new NativePickerResult([], message));
  }

  private isCancellation(error: Error): boolean {
    const message = error.message.toLowerCase();
    return message.includes('cancel') || message.includes('取消');
  }

  private errorMessage(error: Error, fallback: string): string {
    return error.message.length === 0 ? fallback : error.message;
  }
}
