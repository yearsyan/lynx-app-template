import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { camera, cameraPicker } from '@kit.CameraKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { LynxContext, LynxModule } from '@lynx/lynx';

interface NativeCameraOptions {
  lens?: string;
}

export class CameraPhoto {
  uri: string;
  width: number;
  height: number;
  mimeType: string = 'image/jpeg';
  sizeBytes: number;

  constructor(uri: string, width: number, height: number, sizeBytes: number) {
    this.uri = uri;
    this.width = width;
    this.height = height;
    this.sizeBytes = sizeBytes;
  }
}

class CameraOutcome {
  code: string;
  photo: CameraPhoto | null;
  message: string;

  constructor(code: string, photo: CameraPhoto | null, message: string = '') {
    this.code = code;
    this.photo = photo;
    this.message = message;
  }
}

class CameraEnvelope {
  value: CameraOutcome | null;
  error: string;

  constructor(value: CameraOutcome | null, error: string = '') {
    this.value = value;
    this.error = error;
  }
}

/** Opens the HarmonyOS system camera picker and returns a cache/media URI. */
export class CameraModule extends LynxModule {
  static readonly NAME: string = 'Camera';
  private readonly abilityContext: common.UIAbilityContext;
  private isTakingPhoto: boolean = false;

  constructor(context: LynxContext, param?: Object) {
    super(context, param);
    this.abilityContext = getContext(this) as common.UIAbilityContext;
  }

  takePhoto(options: NativeCameraOptions,
    callback: (resultJSON: string) => void): void {
    const lens: string = options?.lens ?? 'back';
    if (lens !== 'back' && lens !== 'front') {
      callback(this.encodeError('Camera lens must be back or front'));
      return;
    }
    if (this.isTakingPhoto) {
      callback(this.encodeOutcome(
        'busy', null, 'Another system camera request is already active'));
      return;
    }

    this.isTakingPhoto = true;
    // PickerProfile is exposed as a class by the SDK typings, but the API 24
    // runtime returns a read-only native-backed instance from `new`. Huawei's
    // CameraPicker examples construct the profile as an object literal.
    const profile: cameraPicker.PickerProfile = {
      cameraPosition: lens === 'front'
        ? camera.CameraPosition.CAMERA_POSITION_FRONT
        : camera.CameraPosition.CAMERA_POSITION_BACK,
    };
    cameraPicker.pick(
      this.abilityContext,
      [cameraPicker.PickerMediaType.PHOTO],
      profile,
    )
      .then(async (result: cameraPicker.PickerResult) => {
        this.isTakingPhoto = false;
        if (result.resultCode !== 0 || result.resultUri.length === 0) {
          callback(this.encodeOutcome(
            'userCancel', null, 'The user cancelled the camera'));
          return;
        }
        try {
          const photo = await this.readPhoto(result.resultUri);
          callback(this.encodeOutcome('success', photo));
        } catch (error) {
          callback(this.encodeOutcome(
            'unavailable', null, this.errorMessage(
              error, 'Unable to read the captured photo')));
        }
      })
      .catch((error: BusinessError) => {
        this.isTakingPhoto = false;
        const message: string = this.errorMessage(
          error, 'Unable to open the system camera');
        const cancelled: boolean = message.toLowerCase().includes('cancel');
        callback(this.encodeOutcome(
          cancelled ? 'userCancel' : 'unavailable', null, message));
      });
  }

  private async readPhoto(uri: string): Promise<CameraPhoto> {
    const source: image.ImageSource = image.createImageSource(uri);
    try {
      const info: image.ImageInfo = await source.getImageInfo();
      let sizeBytes: number = 0;
      try {
        const path: string = uri.startsWith('file://')
          ? uri.substring('file://'.length)
          : uri;
        sizeBytes = fs.statSync(path).size;
      } catch (_error) {
        // Some system camera providers expose a media URI whose file size is
        // intentionally opaque. Dimensions and the URI remain usable.
      }
      return new CameraPhoto(uri, info.size.width, info.size.height, sizeBytes);
    } finally {
      source.release();
    }
  }

  private encodeOutcome(code: string, photo: CameraPhoto | null,
    message: string = ''): string {
    return JSON.stringify(new CameraEnvelope(
      new CameraOutcome(code, photo, message)));
  }

  private encodeError(message: string): string {
    return JSON.stringify(new CameraEnvelope(null, message));
  }

  private errorMessage(error: Object, fallback: string): string {
    const typed = error as Error;
    return typed.message !== undefined && typed.message.length > 0
      ? typed.message
      : fallback;
  }
}
