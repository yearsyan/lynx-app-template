import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { camera } from '@kit.CameraKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import {
  EventHandlerArray,
  IContext,
  LynxUIMethodConstants,
  UIBase,
} from '@lynx/lynx';
import { CameraPhoto } from './CameraModule';

type UIMethodCallback = (code: number, res: Object) => void;

class EmptyResult {
}

@ObservedV2
class CameraViewState {
  @Trace renderFitMode: RenderFit = RenderFit.RESIZE_COVER;
  readonly controller: XComponentController = new XComponentController();
  readonly ui: CameraViewUI;

  constructor(ui: CameraViewUI) {
    this.ui = ui;
  }

  onSurfaceLoad(): void {
    const surfaceID: string = this.controller.getXComponentSurfaceId();
    this.ui.onSurfaceAvailable(surfaceID);
  }

  onSurfaceDestroy(): void {
    this.ui.onSurfaceDestroyed();
  }

  onAreaChange(area: Area): void {
    this.ui.setPreviewArea(
      vp2px(Number(area.width)),
      vp2px(Number(area.height)),
    );
  }

  setPreviewFit(value: string): void {
    this.renderFitMode = value === 'contain'
      ? RenderFit.RESIZE_CONTAIN
      : RenderFit.RESIZE_COVER;
  }
}

@ComponentV2
struct CameraViewComponent {
  @Param @Require state: CameraViewState;

  build() {
    Stack() {
      XComponent({
        type: XComponentType.SURFACE,
        controller: this.state.controller,
      })
        .width('100%')
        .height('100%')
        .renderFit(this.state.renderFitMode)
        .onLoad(() => {
          this.state.onSurfaceLoad();
        })
        .onDestroy(() => {
          this.state.onSurfaceDestroy();
        });
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Black)
    .clip(true)
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      this.state.onAreaChange(newValue);
    });
  }
}

@Builder
function buildCameraView(ui: UIBase) {
  CameraViewComponent({ state: (ui as CameraViewUI).state });
}

/** CameraKit-backed inline preview for `<x-camera-view>`. */
export class CameraViewUI extends UIBase {
  static readonly NAME: string = 'x-camera-view';
  private static nextCacheID: number = 0;

  readonly state: CameraViewState = new CameraViewState(this);
  readonly builder: WrappedBuilder<[UIBase]> = wrapBuilder(buildCameraView);

  private surfaceID: string = '';
  private previewWidth: number = 0;
  private previewHeight: number = 0;
  private session: camera.PhotoSession | undefined = undefined;
  private cameraInput: camera.CameraInput | undefined = undefined;
  private previewOutput: camera.PreviewOutput | undefined = undefined;
  private photoOutput: camera.PhotoOutput | undefined = undefined;
  private active: boolean = true;
  private lens: string = 'back';
  private zoom: number = 1;
  private torch: boolean = false;
  private flash: string = 'auto';
  private exposureCompensation: number = 0;
  private photoQuality: number = 92;
  private mirrorPhoto: boolean = true;
  private previewFit: string = 'cover';
  private cameraState: string = 'stopped';
  private permissionRequestInFlight: boolean = false;
  private permissionDenied: boolean = false;
  private generation: number = 0;
  private captureCallback: UIMethodCallback | undefined = undefined;

  constructor(context: IContext, param?: Object) {
    super(context, param);
  }

  layout(x: number, y: number, width: number, height: number,
    paddingLeft: number, paddingTop: number, paddingRight: number,
    paddingBottom: number, marginLeft: number, marginTop: number,
    marginRight: number, marginBottom: number, sticky?: number[]): void {
    // The ArkUI Stack and XComponent fill Lynx's FrameNode.
  }

  update(props: Record<string, Object>, events?: EventHandlerArray[]): void {
    super.update(props, events);
    const active = props['active'];
    if (typeof active === 'boolean' && active !== this.active) {
      this.active = active;
      if (active) {
        this.startIfPossible();
      } else {
        this.stopCamera();
      }
    }
    const lens = props['lens'];
    if (typeof lens === 'string') {
      const normalized: string = lens === 'front' ? 'front' : 'back';
      if (normalized !== this.lens) {
        this.lens = normalized;
        this.restartIfPossible();
      }
    }
    const zoom = props['zoom'];
    if (typeof zoom === 'number') {
      this.zoom = Math.max(1, zoom);
      this.applyControls();
    }
    const torch = props['torch'];
    if (typeof torch === 'string') {
      this.torch = torch === 'on';
      this.applyTorch();
    }
    const flash = props['flash'];
    if (typeof flash === 'string') {
      this.flash = flash === 'on' || flash === 'off' ? flash : 'auto';
    }
    const exposure = props['exposure-compensation'];
    if (typeof exposure === 'number') {
      this.exposureCompensation = exposure;
      this.applyControls();
    }
    const quality = props['photo-quality'];
    if (typeof quality === 'number') {
      this.photoQuality = Math.max(1, Math.min(100, Math.round(quality)));
    }
    const mirror = props['mirror-photo'];
    if (typeof mirror === 'boolean') {
      this.mirrorPhoto = mirror;
    }
    const fit = props['preview-fit'];
    if (typeof fit === 'string') {
      this.previewFit = fit === 'contain' ? 'contain' : 'cover';
      this.state.setPreviewFit(this.previewFit);
    }
  }

  invokeMethod(method: string, params: Object,
    callback: UIMethodCallback): boolean {
    if (method === 'capture') {
      this.capture(callback);
      return true;
    }
    if (method === 'focusAtPoint') {
      const record = params as Record<string, Object>;
      const x = record['x'];
      const y = record['y'];
      if (typeof x !== 'number' || typeof y !== 'number' ||
        !Number.isFinite(x) || !Number.isFinite(y) ||
        x < 0 || x > 1 || y < 0 || y > 1) {
        callback(LynxUIMethodConstants.PARAM_INVALID,
          'Camera focus coordinates must be in [0, 1]');
        return true;
      }
      this.focusAtPoint(x, y, callback);
      return true;
    }
    return false;
  }

  onEnterForeground(): void {
    this.startIfPossible();
  }

  onEnterBackground(): void {
    this.stopCamera();
  }

  onSurfaceAvailable(surfaceID: string): void {
    this.surfaceID = surfaceID;
    this.startIfPossible();
  }

  onSurfaceDestroyed(): void {
    this.surfaceID = '';
    this.stopCamera();
  }

  setPreviewArea(width: number, height: number): void {
    const wasMeasured: boolean = this.previewWidth > 0 && this.previewHeight > 0;
    this.previewWidth = width;
    this.previewHeight = height;
    if (!wasMeasured && width > 0 && height > 0) {
      this.startIfPossible();
    }
  }

  private startIfPossible(): void {
    if (!this.active || this.surfaceID.length === 0 ||
      this.previewWidth <= 0 || this.previewHeight <= 0) {
      return;
    }
    this.ensurePermission()
      .then((granted: boolean) => {
        if (granted && this.active && this.surfaceID.length > 0) {
          this.startCamera();
        }
      })
      .catch((error: Error) => {
        this.updateState('stopped');
        this.emitError('configurationFailed',
          this.errorMessage(error, 'Unable to request camera permission'));
      });
  }

  private async ensurePermission(): Promise<boolean> {
    if (this.permissionRequestInFlight || this.permissionDenied) {
      return false;
    }
    const abilityContext = this.abilityContext();
    if (abilityContext === undefined) {
      throw new Error('x-camera-view has no UIAbilityContext');
    }
    this.permissionRequestInFlight = true;
    this.updateState('requestingPermission');
    try {
      const result = await abilityAccessCtrl.createAtManager()
        .requestPermissionsFromUser(
          abilityContext,
          ['ohos.permission.CAMERA' as Permissions],
        );
      const granted: boolean = result.authResults.length > 0 &&
        result.authResults[0] === 0;
      this.permissionDenied = !granted;
      if (!granted) {
        this.updateState('stopped');
        this.emitError('permissionDenied', 'Camera permission was denied');
      }
      return granted;
    } finally {
      this.permissionRequestInFlight = false;
    }
  }

  private async startCamera(): Promise<void> {
    const generation: number = ++this.generation;
    this.updateState('starting');
    await this.releaseCurrentCamera();
    if (generation !== this.generation || !this.active || this.surfaceID.length === 0) {
      return;
    }

    let input: camera.CameraInput | undefined = undefined;
    let preview: camera.PreviewOutput | undefined = undefined;
    let photo: camera.PhotoOutput | undefined = undefined;
    let session: camera.PhotoSession | undefined = undefined;
    try {
      const abilityContext = this.abilityContext();
      if (abilityContext === undefined) {
        throw new Error('x-camera-view has no UIAbilityContext');
      }
      const manager: camera.CameraManager = camera.getCameraManager(abilityContext);
      const device: camera.CameraDevice | undefined = this.selectCamera(
        manager.getSupportedCameras());
      if (device === undefined) {
        throw new Error('The selected camera is unavailable');
      }
      const capability: camera.CameraOutputCapability =
        manager.getSupportedOutputCapability(device, camera.SceneMode.NORMAL_PHOTO);
      const previewProfile: camera.Profile | undefined =
        this.selectPreviewProfile(capability.previewProfiles);
      const photoProfile: camera.Profile | undefined =
        previewProfile === undefined
          ? undefined
          : this.selectPhotoProfile(capability.photoProfiles, previewProfile);
      if (previewProfile === undefined || photoProfile === undefined) {
        throw new Error('The selected camera has no compatible photo profiles');
      }

      input = manager.createCameraInput(device);
      await input.open();
      if (generation !== this.generation) {
        await this.releaseResources(session, input, preview, photo);
        return;
      }
      preview = manager.createPreviewOutput(previewProfile, this.surfaceID);
      photo = manager.createPhotoOutput(photoProfile);
      photo.on('photoAvailable', (error: BusinessError, captured: camera.Photo) => {
        if (error !== undefined && error !== null) {
          this.finishCaptureError(this.errorMessage(error, 'Unable to capture a photo'));
          return;
        }
        this.consumePhoto(captured);
      });
      session = manager.createSession<camera.PhotoSession>(
        camera.SceneMode.NORMAL_PHOTO);
      session.beginConfig();
      session.addInput(input);
      session.addOutput(preview);
      session.addOutput(photo);
      await session.commitConfig();
      await session.start();
      if (generation !== this.generation) {
        await this.releaseResources(session, input, preview, photo);
        return;
      }

      this.cameraInput = input;
      this.previewOutput = preview;
      this.photoOutput = photo;
      this.session = session;
      this.applyControls();
      this.updateState('ready');
      this.emitReady();
    } catch (error) {
      await this.releaseResources(session, input, preview, photo);
      if (generation === this.generation) {
        this.updateState('stopped');
        const message: string = this.errorMessage(
          error as Error, 'Unable to start the selected camera');
        this.emitError(
          message.includes('unavailable') ? 'unavailable' : 'configurationFailed',
          message,
        );
      }
    }
  }

  private restartIfPossible(): void {
    if (this.active && this.surfaceID.length > 0 && !this.permissionDenied) {
      this.startCamera();
    }
  }

  private stopCamera(): void {
    this.generation += 1;
    this.updateState('stopped');
    if (this.captureCallback !== undefined) {
      const callback = this.captureCallback;
      this.captureCallback = undefined;
      callback(LynxUIMethodConstants.INVALID_STATE_ERROR,
        'Camera stopped during photo capture');
    }
    this.releaseCurrentCamera();
  }

  private async releaseCurrentCamera(): Promise<void> {
    const session = this.session;
    const input = this.cameraInput;
    const preview = this.previewOutput;
    const photo = this.photoOutput;
    this.session = undefined;
    this.cameraInput = undefined;
    this.previewOutput = undefined;
    this.photoOutput = undefined;
    await this.releaseResources(session, input, preview, photo);
  }

  private async releaseResources(
    session: camera.PhotoSession | undefined,
    input: camera.CameraInput | undefined,
    preview: camera.PreviewOutput | undefined,
    photo: camera.PhotoOutput | undefined,
  ): Promise<void> {
    if (photo !== undefined) {
      photo.off('photoAvailable');
    }
    if (session !== undefined) {
      try {
        await session.stop();
      } catch (_error) {
      }
      try {
        await session.release();
      } catch (_error) {
      }
    }
    if (preview !== undefined) {
      try {
        await preview.release();
      } catch (_error) {
      }
    }
    if (photo !== undefined) {
      try {
        await photo.release();
      } catch (_error) {
      }
    }
    if (input !== undefined) {
      try {
        await input.close();
      } catch (_error) {
      }
    }
  }

  private selectCamera(devices: Array<camera.CameraDevice>): camera.CameraDevice | undefined {
    const position: camera.CameraPosition = this.lens === 'front'
      ? camera.CameraPosition.CAMERA_POSITION_FRONT
      : camera.CameraPosition.CAMERA_POSITION_BACK;
    for (let index = 0; index < devices.length; index += 1) {
      if (devices[index].cameraPosition === position) {
        return devices[index];
      }
    }
    return undefined;
  }

  private selectPreviewProfile(profiles: Array<camera.Profile>): camera.Profile | undefined {
    if (profiles.length === 0) {
      return undefined;
    }
    const targetAspect: number = this.previewWidth > 0 && this.previewHeight > 0
      ? Math.max(this.previewWidth, this.previewHeight) /
        Math.min(this.previewWidth, this.previewHeight)
      : 16 / 9;
    let best: camera.Profile = profiles[0];
    let bestScore: number = Number.MAX_VALUE;
    for (let index = 0; index < profiles.length; index += 1) {
      const profile = profiles[index];
      const aspect: number = Math.max(profile.size.width, profile.size.height) /
        Math.min(profile.size.width, profile.size.height);
      const area: number = profile.size.width * profile.size.height;
      const areaPenalty: number = area > 4000000 ? (area - 4000000) / 4000000 : 0;
      const score: number = Math.abs(aspect - targetAspect) + areaPenalty * 0.05;
      if (score < bestScore) {
        best = profile;
        bestScore = score;
      }
    }
    return best;
  }

  private selectPhotoProfile(
    profiles: Array<camera.Profile>,
    previewProfile: camera.Profile,
  ): camera.Profile | undefined {
    let best: camera.Profile | undefined = undefined;
    let bestAspectDifference: number = Number.MAX_VALUE;
    let bestArea: number = 0;
    const previewAspect: number = Math.max(
      previewProfile.size.width, previewProfile.size.height) /
      Math.min(previewProfile.size.width, previewProfile.size.height);
    for (let index = 0; index < profiles.length; index += 1) {
      const profile = profiles[index];
      if (profile.format !== camera.CameraFormat.CAMERA_FORMAT_JPEG) {
        continue;
      }
      const aspect: number = Math.max(profile.size.width, profile.size.height) /
        Math.min(profile.size.width, profile.size.height);
      const aspectDifference: number = Math.abs(aspect - previewAspect);
      const area: number = profile.size.width * profile.size.height;
      if (best === undefined || aspectDifference < bestAspectDifference - 0.001 ||
        (Math.abs(aspectDifference - bestAspectDifference) <= 0.001 && area > bestArea)) {
        best = profile;
        bestAspectDifference = aspectDifference;
        bestArea = area;
      }
    }
    return best ?? (profiles.length > 0 ? profiles[0] : undefined);
  }

  private applyControls(): void {
    const session = this.session;
    if (session === undefined) {
      return;
    }
    try {
      const zoomRange: Array<number> = session.getZoomRatioRange();
      const zoomBounds = this.boundsOf(zoomRange, 1, 1);
      session.setZoomRatio(Math.max(zoomBounds[0], Math.min(zoomBounds[1], this.zoom)));
      const exposureRange: Array<number> = session.getExposureBiasRange();
      const exposureBounds = this.boundsOf(exposureRange, 0, 0);
      session.setExposureBias(Math.max(
        exposureBounds[0], Math.min(exposureBounds[1], this.exposureCompensation)));
      if (session.isFocusModeSupported(camera.FocusMode.FOCUS_MODE_CONTINUOUS_AUTO)) {
        session.setFocusMode(camera.FocusMode.FOCUS_MODE_CONTINUOUS_AUTO);
      }
      this.applyTorch();
    } catch (error) {
      this.emitError('configurationFailed', this.errorMessage(
        error as Error, 'Unable to apply camera controls'));
    }
  }

  private applyTorch(): void {
    const session = this.session;
    if (session === undefined) {
      return;
    }
    const mode: camera.FlashMode = this.torch
      ? camera.FlashMode.FLASH_MODE_ALWAYS_OPEN
      : camera.FlashMode.FLASH_MODE_CLOSE;
    try {
      if (session.isFlashModeSupported(mode)) {
        session.setFlashMode(mode);
      }
    } catch (_error) {
      // Torch support is reported by ready; unsupported requests are ignored.
    }
  }

  private capture(callback: UIMethodCallback): void {
    const session = this.session;
    const output = this.photoOutput;
    if (session === undefined || output === undefined || this.cameraState !== 'ready') {
      callback(LynxUIMethodConstants.INVALID_STATE_ERROR, 'Camera is not ready');
      return;
    }
    if (this.captureCallback !== undefined) {
      callback(LynxUIMethodConstants.INVALID_STATE_ERROR,
        'A photo capture is already in progress');
      return;
    }
    this.captureCallback = callback;
    const flashMode: camera.FlashMode = this.flash === 'on'
      ? camera.FlashMode.FLASH_MODE_OPEN
      : this.flash === 'off'
        ? camera.FlashMode.FLASH_MODE_CLOSE
        : camera.FlashMode.FLASH_MODE_AUTO;
    try {
      if (!this.torch && session.isFlashModeSupported(flashMode)) {
        session.setFlashMode(flashMode);
      }
      const quality: camera.QualityLevel = this.photoQuality >= 85
        ? camera.QualityLevel.QUALITY_LEVEL_HIGH
        : this.photoQuality >= 50
          ? camera.QualityLevel.QUALITY_LEVEL_MEDIUM
          : camera.QualityLevel.QUALITY_LEVEL_LOW;
      const setting: camera.PhotoCaptureSetting = { quality };
      if (this.lens === 'front' && this.mirrorPhoto && output.isMirrorSupported()) {
        setting.mirror = true;
      }
      output.capture(setting).catch((error: BusinessError) => {
        this.finishCaptureError(this.errorMessage(error, 'Unable to capture a photo'));
      });
    } catch (error) {
      this.finishCaptureError(this.errorMessage(
        error as Error, 'Unable to capture a photo'));
    }
  }

  private async consumePhoto(photo: camera.Photo): Promise<void> {
    try {
      const size: image.Size = photo.main.size;
      const component: image.Component = await photo.main.getComponent(
        image.ComponentType.JPEG);
      const buffer: ArrayBuffer = component.byteBuffer;
      const uri: string = this.writeCacheJPEG(buffer);
      const result = new CameraPhoto(
        uri, size.width, size.height, buffer.byteLength);
      this.sendCustomEvent('capture', { 'photo': result }, 'detail');
      const callback = this.captureCallback;
      this.captureCallback = undefined;
      if (callback !== undefined) {
        callback(LynxUIMethodConstants.SUCCESS, result);
      }
    } catch (error) {
      this.finishCaptureError(this.errorMessage(
        error as Error, 'Unable to save the captured photo'));
    } finally {
      await photo.release();
      this.applyTorch();
    }
  }

  private finishCaptureError(message: string): void {
    this.emitError('captureFailed', message);
    const callback = this.captureCallback;
    this.captureCallback = undefined;
    if (callback !== undefined) {
      callback(LynxUIMethodConstants.OPERATION_ERROR, message);
    }
    this.applyTorch();
  }

  private focusAtPoint(x: number, y: number, callback: UIMethodCallback): void {
    const session = this.session;
    if (session === undefined || this.cameraState !== 'ready') {
      callback(LynxUIMethodConstants.INVALID_STATE_ERROR, 'Camera is not ready');
      return;
    }
    try {
      const point: camera.Point = { x, y };
      if (session.isFocusModeSupported(camera.FocusMode.FOCUS_MODE_AUTO)) {
        session.setFocusMode(camera.FocusMode.FOCUS_MODE_AUTO);
      }
      session.setFocusPoint(point);
      session.setMeteringPoint(point);
      callback(LynxUIMethodConstants.SUCCESS, new EmptyResult());
    } catch (error) {
      callback(LynxUIMethodConstants.OPERATION_ERROR,
        this.errorMessage(error as Error, 'Unable to focus the camera'));
    }
  }

  private emitReady(): void {
    const session = this.session;
    if (session === undefined) {
      return;
    }
    let zoomBounds: [number, number] = [1, 1];
    let exposureBounds: [number, number] = [0, 0];
    let torchSupported: boolean = false;
    try {
      zoomBounds = this.boundsOf(session.getZoomRatioRange(), 1, 1);
    } catch (_error) {
      // Capability queries vary across devices; a preview can still be ready.
    }
    try {
      exposureBounds = this.boundsOf(session.getExposureBiasRange(), 0, 0);
    } catch (_error) {
    }
    try {
      torchSupported = session.hasFlash();
    } catch (_error) {
    }
    const appliedZoom: number = Math.max(
      zoomBounds[0], Math.min(zoomBounds[1], this.zoom));
    this.sendCustomEvent('ready', {
      'lens': this.lens,
      'zoom': appliedZoom,
      'minZoom': zoomBounds[0],
      'maxZoom': zoomBounds[1],
      'torchSupported': torchSupported,
      'exposureMin': exposureBounds[0],
      'exposureMax': exposureBounds[1],
    }, 'detail');
  }

  private updateState(state: string): void {
    if (this.cameraState === state) {
      return;
    }
    this.cameraState = state;
    this.sendCustomEvent('statechange', { 'state': state }, 'detail');
  }

  private emitError(code: string, message: string): void {
    this.sendCustomEvent('error', {
      'code': code,
      'message': message,
    }, 'detail');
  }

  private writeCacheJPEG(buffer: ArrayBuffer): string {
    const abilityContext = this.abilityContext();
    if (abilityContext === undefined) {
      throw new Error('x-camera-view has no UIAbilityContext');
    }
    const directory: string = `${abilityContext.cacheDir}/LynxCamera`;
    if (!fs.accessSync(directory)) {
      fs.mkdirSync(directory, true);
    }
    CameraViewUI.nextCacheID += 1;
    const path: string = `${directory}/${Date.now()}-${CameraViewUI.nextCacheID}.jpg`;
    const file: fs.File = fs.openSync(
      path,
      fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC,
    );
    try {
      fs.writeSync(file.fd, buffer);
    } finally {
      fs.closeSync(file);
    }
    return `file://${path}`;
  }

  private boundsOf(values: Array<number>, defaultMin: number,
    defaultMax: number): [number, number] {
    if (values.length === 0) {
      return [defaultMin, defaultMax];
    }
    let minimum: number = values[0];
    let maximum: number = values[0];
    for (let index = 1; index < values.length; index += 1) {
      minimum = Math.min(minimum, values[index]);
      maximum = Math.max(maximum, values[index]);
    }
    return [minimum, maximum];
  }

  private abilityContext(): common.UIAbilityContext | undefined {
    return this.uiContext?.getHostContext() as common.UIAbilityContext | undefined;
  }

  private errorMessage(error: Object, fallback: string): string {
    const typed = error as Error;
    return typed.message !== undefined && typed.message.length > 0
      ? typed.message
      : fallback;
  }

  dispose(): void {
    this.active = false;
    this.surfaceID = '';
    this.stopCamera();
    super.dispose();
  }
}
