import type { StandardProps } from '@lynx-js/types';
import {
  decodeNativeEnvelope,
  requireNativeModule,
} from './bridge.generated.js';

export * from './native.generated.js';

export const CAMERA_VIEW_ELEMENT_NAME = 'x-camera-view';

export type CameraLens = 'back' | 'front';
export type CameraFlashMode = 'off' | 'on' | 'auto';
export type CameraTorchMode = 'off' | 'on';
export type CameraPreviewFit = 'cover' | 'contain';

export interface CameraPhoto {
  /** Local result URI. Treat it as opaque rather than as a cross-platform path. */
  readonly uri: string;
  readonly width: number;
  readonly height: number;
  readonly mimeType: 'image/jpeg';
  readonly sizeBytes: number;
}

export type CameraCaptureCode =
  | 'success'
  | 'userCancel'
  | 'permissionDenied'
  | 'unavailable'
  | 'busy';

export interface CameraCaptureOutcome {
  readonly success: boolean;
  readonly code: CameraCaptureCode;
  readonly photo: CameraPhoto | null;
  /** Native diagnostic intended for logs rather than direct user display. */
  readonly message: string;
}

export interface TakePhotoOptions {
  /** Preferred initial system-camera lens. Defaults to `back`. */
  lens?: CameraLens;
}

export type CameraViewState =
  | 'requestingPermission'
  | 'starting'
  | 'ready'
  | 'stopped';

export interface CameraViewReadyDetail {
  lens: CameraLens;
  zoom: number;
  minZoom: number;
  maxZoom: number;
  torchSupported: boolean;
  exposureMin: number;
  exposureMax: number;
}

export interface CameraViewStateDetail {
  state: CameraViewState;
}

export type CameraViewErrorCode =
  | 'permissionDenied'
  | 'unavailable'
  | 'configurationFailed'
  | 'captureFailed';

export interface CameraViewErrorDetail {
  code: CameraViewErrorCode;
  message: string;
}

export interface CameraViewCaptureDetail {
  photo: CameraPhoto;
}

export interface CameraViewReadyEvent {
  type: 'ready';
  detail: CameraViewReadyDetail;
}

export interface CameraViewStateEvent {
  type: 'statechange';
  detail: CameraViewStateDetail;
}

export interface CameraViewErrorEvent {
  type: 'error';
  detail: CameraViewErrorDetail;
}

export interface CameraViewCaptureEvent {
  type: 'capture';
  detail: CameraViewCaptureDetail;
}

/** JSX contract for the native inline camera preview. */
export interface CameraViewProps extends StandardProps {
  /** Starts/stops the camera without removing the element. Defaults to true. */
  active?: boolean;
  /** Selects the back or front camera. Defaults to back. */
  lens?: CameraLens;
  /** Optical/digital zoom factor. Native code clamps to the device range. */
  zoom?: number;
  /** Continuous preview light. Defaults to off. */
  torch?: CameraTorchMode;
  /** Flash used by the `capture` command. Defaults to auto. */
  flash?: CameraFlashMode;
  /** Exposure compensation in EV. Native code clamps to the device range. */
  'exposure-compensation'?: number;
  /** JPEG quality for inline captures, an integer from 1 to 100. */
  'photo-quality'?: number;
  /** Mirrors front-camera photos. Preview mirroring remains platform-native. */
  'mirror-photo'?: boolean;
  /** `cover` center-crops without stretching; `contain` letterboxes. */
  'preview-fit'?: CameraPreviewFit;
  bindready?: (event: CameraViewReadyEvent) => void;
  bindstatechange?: (event: CameraViewStateEvent) => void;
  binderror?: (event: CameraViewErrorEvent) => void;
  bindcapture?: (event: CameraViewCaptureEvent) => void;
}

interface CameraEnvelope {
  value?: unknown;
  error?: unknown;
}

const CAPTURE_CODES: readonly string[] = [
  'success',
  'userCancel',
  'permissionDenied',
  'unavailable',
  'busy',
];

function requireCameraModule() {
  'background only';
  return requireNativeModule();
}

function decodePhoto(value: unknown): CameraPhoto {
  'background only';
  if (typeof value !== 'object' || value === null) {
    throw new Error('Camera returned an invalid photo');
  }
  const photo = value as Partial<CameraPhoto>;
  if (
    typeof photo.uri !== 'string' ||
    photo.uri.length === 0 ||
    typeof photo.width !== 'number' ||
    !Number.isFinite(photo.width) ||
    photo.width <= 0 ||
    typeof photo.height !== 'number' ||
    !Number.isFinite(photo.height) ||
    photo.height <= 0 ||
    photo.mimeType !== 'image/jpeg' ||
    typeof photo.sizeBytes !== 'number' ||
    !Number.isFinite(photo.sizeBytes) ||
    photo.sizeBytes < 0
  ) {
    throw new Error('Camera returned malformed photo metadata');
  }
  return {
    uri: photo.uri,
    width: Math.round(photo.width),
    height: Math.round(photo.height),
    mimeType: 'image/jpeg',
    sizeBytes: Math.round(photo.sizeBytes),
  };
}

function decodeOutcome(value: unknown): CameraCaptureOutcome {
  'background only';
  if (typeof value !== 'object' || value === null) {
    throw new Error('Camera returned an invalid capture outcome');
  }
  const outcome = value as {
    code?: unknown;
    photo?: unknown;
    message?: unknown;
  };
  if (
    typeof outcome.code !== 'string' ||
    !CAPTURE_CODES.includes(outcome.code)
  ) {
    throw new Error('Camera returned an invalid capture code');
  }
  const success = outcome.code === 'success';
  return {
    success,
    code: outcome.code as CameraCaptureCode,
    photo: success ? decodePhoto(outcome.photo) : null,
    message: typeof outcome.message === 'string' ? outcome.message : '',
  };
}

function validateSelector(selector: string): string {
  'background only';
  const normalized = selector.trim();
  if (!normalized.startsWith('#') || normalized.length < 2) {
    throw new Error(
      'Camera view commands require an ID selector such as #camera',
    );
  }
  return normalized;
}

function invokeCameraView<T>(
  selector: string,
  method: string,
  params: Record<string, unknown>,
  decode: (value: unknown) => T,
): Promise<T> {
  'background only';
  const normalized = validateSelector(selector);
  return new Promise((resolve, reject) => {
    lynx
      .createSelectorQuery()
      .select(normalized)
      .invoke({
        method,
        params,
        success: (value: unknown) => {
          'background only';
          try {
            resolve(decode(value));
          } catch (error) {
            reject(error instanceof Error ? error : new Error(String(error)));
          }
        },
        fail: (failure) => {
          'background only';
          const detail =
            typeof failure.data === 'string' && failure.data.length > 0
              ? failure.data
              : `native error ${failure.code}`;
          reject(new Error(`Camera view ${method} failed: ${detail}`));
        },
      })
      .exec();
  });
}

/** Opens the platform's user-visible system camera. */
export const camera = {
  takePhoto(options: TakePhotoOptions = {}): Promise<CameraCaptureOutcome> {
    'background only';
    const lens = options.lens ?? 'back';
    if (lens !== 'back' && lens !== 'front') {
      throw new Error(`Invalid camera lens: ${String(lens)}`);
    }
    return new Promise((resolve, reject) => {
      try {
        requireCameraModule().takePhoto({ lens }, (result) => {
          'background only';
          try {
            const envelope = decodeNativeEnvelope(
              result,
              'Camera',
            ) as CameraEnvelope;
            if (
              typeof envelope.error === 'string' &&
              envelope.error.length > 0
            ) {
              reject(new Error(envelope.error));
              return;
            }
            resolve(decodeOutcome(envelope.value));
          } catch (error) {
            reject(error instanceof Error ? error : new Error(String(error)));
          }
        });
      } catch (error) {
        reject(error instanceof Error ? error : new Error(String(error)));
      }
    });
  },
};

/** Imperative commands exposed by `<x-camera-view>`. */
export const cameraView = {
  capture(selector: string): Promise<CameraPhoto> {
    'background only';
    return invokeCameraView(selector, 'capture', {}, decodePhoto);
  },

  focusAtPoint(selector: string, x: number, y: number): Promise<void> {
    'background only';
    if (
      !Number.isFinite(x) ||
      !Number.isFinite(y) ||
      x < 0 ||
      x > 1 ||
      y < 0 ||
      y > 1
    ) {
      throw new Error('Camera focus coordinates must be normalized to [0, 1]');
    }
    return invokeCameraView(
      selector,
      'focusAtPoint',
      { x, y },
      () => undefined,
    );
  },
};

// IntrinsicElements is augmented by each consumer so the declaration merges
// into the consumer's catalog-pinned @lynx-js/types instance.
