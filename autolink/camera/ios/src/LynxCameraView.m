#import "CameraPhotoUtils.h"

#import <AVFoundation/AVFoundation.h>
#import <Lynx/LynxEvent.h>
#import <Lynx/LynxEventEmitter.h>
#import <Lynx/LynxPropsProcessor.h>
#import <Lynx/LynxUI.h>
#import <Lynx/LynxUIMethodProcessor.h>
#import <UIKit/UIKit.h>
#import <math.h>

@class LynxUICameraView;

typedef void (^LynxCameraCaptureCompletion)(NSDictionary *_Nullable photo,
                                            NSString *_Nullable errorMessage);
typedef void (^LynxCameraOperationCompletion)(NSString *_Nullable errorMessage);

@interface LynxCameraPreviewContainer : UIView <AVCapturePhotoCaptureDelegate>

@property(nonatomic, weak) LynxUICameraView *owner;
@property(nonatomic, assign, getter=isCameraActive) BOOL cameraActive;
@property(nonatomic, copy) NSString *lens;
@property(nonatomic, assign) CGFloat requestedZoom;
@property(nonatomic, assign, getter=isTorchEnabled) BOOL torchEnabled;
@property(nonatomic, assign) AVCaptureFlashMode flashMode;
@property(nonatomic, assign) CGFloat exposureCompensation;
@property(nonatomic, assign) NSInteger photoQuality;
@property(nonatomic, assign) BOOL mirrorPhoto;

- (void)setPreviewFit:(NSString *)fit;
- (void)captureWithCompletion:(LynxCameraCaptureCompletion)completion;
- (void)focusAtNormalizedPoint:(CGPoint)point
                    completion:(LynxCameraOperationCompletion)completion;
- (void)dispose;

@end

@interface LynxUICameraView : LynxUI<LynxCameraPreviewContainer *>

- (void)emitReady:(NSDictionary *)detail;
- (void)emitState:(NSString *)state;
- (void)emitErrorCode:(NSString *)code message:(NSString *)message;
- (void)emitCapture:(NSDictionary *)photo;

@end

@implementation LynxCameraPreviewContainer {
  AVCaptureSession *_session;
  AVCaptureVideoPreviewLayer *_previewLayer;
  AVCaptureDevice *_device;
  AVCaptureDeviceInput *_deviceInput;
  AVCapturePhotoOutput *_photoOutput;
  dispatch_queue_t _sessionQueue;
  NSString *_state;
  NSUInteger _generation;
  BOOL _permissionRequestInFlight;
  BOOL _permissionDenied;
  LynxCameraCaptureCompletion _captureCompletion;
  BOOL _captureMirror;
}

- (instancetype)initWithFrame:(CGRect)frame {
  self = [super initWithFrame:frame];
  if (self) {
    self.backgroundColor = UIColor.blackColor;
    self.clipsToBounds = YES;
    _cameraActive = YES;
    _lens = @"back";
    _requestedZoom = 1.0;
    _flashMode = AVCaptureFlashModeAuto;
    _photoQuality = 92;
    _mirrorPhoto = YES;
    _state = @"stopped";
    _sessionQueue = dispatch_queue_create("lynx.camera.preview", DISPATCH_QUEUE_SERIAL);
    _session = [[AVCaptureSession alloc] init];
    _previewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:_session];
    _previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    [self.layer addSublayer:_previewLayer];
  }
  return self;
}

- (void)layoutSubviews {
  [super layoutSubviews];
  _previewLayer.frame = self.bounds;
  AVCaptureConnection *connection = _previewLayer.connection;
  if (connection.isVideoOrientationSupported) {
    connection.videoOrientation = [self currentVideoOrientation];
  }
}

- (void)didMoveToWindow {
  [super didMoveToWindow];
  if (self.window == nil) {
    [self stopCamera];
  } else {
    [self startIfPossible];
  }
}

- (void)setCameraActive:(BOOL)cameraActive {
  if (_cameraActive == cameraActive) {
    return;
  }
  _cameraActive = cameraActive;
  if (cameraActive) {
    [self startIfPossible];
  } else {
    [self stopCamera];
  }
}

- (void)setLens:(NSString *)lens {
  NSString *normalized = [lens isEqualToString:@"front"] ? @"front" : @"back";
  if ([_lens isEqualToString:normalized]) {
    return;
  }
  _lens = [normalized copy];
  [self reconfigureIfRunning];
}

- (void)setRequestedZoom:(CGFloat)requestedZoom {
  _requestedZoom = MAX(1.0, requestedZoom);
  [self applyControls];
}

- (void)setTorchEnabled:(BOOL)torchEnabled {
  _torchEnabled = torchEnabled;
  [self applyControls];
}

- (void)setExposureCompensation:(CGFloat)exposureCompensation {
  _exposureCompensation = exposureCompensation;
  [self applyControls];
}

- (void)setPhotoQuality:(NSInteger)photoQuality {
  _photoQuality = MAX(1, MIN(100, photoQuality));
}

- (void)setPreviewFit:(NSString *)fit {
  _previewLayer.videoGravity = [fit isEqualToString:@"contain"]
                                   ? AVLayerVideoGravityResizeAspect
                                   : AVLayerVideoGravityResizeAspectFill;
}

- (void)startIfPossible {
  NSAssert(NSThread.isMainThread, @"Camera view lifecycle must run on main thread");
  if (!self.isCameraActive || self.window == nil) {
    return;
  }
  AVAuthorizationStatus status =
      [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
  if (status == AVAuthorizationStatusAuthorized) {
    _permissionDenied = NO;
    [self configureAndStart];
    return;
  }
  if (status == AVAuthorizationStatusNotDetermined && !_permissionRequestInFlight) {
    _permissionRequestInFlight = YES;
    [self updateState:@"requestingPermission"];
    __weak LynxCameraPreviewContainer *weakSelf = self;
    [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo
                             completionHandler:^(BOOL granted) {
      dispatch_async(dispatch_get_main_queue(), ^{
        LynxCameraPreviewContainer *strongSelf = weakSelf;
        if (strongSelf == nil) {
          return;
        }
        strongSelf->_permissionRequestInFlight = NO;
        strongSelf->_permissionDenied = !granted;
        if (granted) {
          [strongSelf startIfPossible];
        } else {
          [strongSelf updateState:@"stopped"];
          [strongSelf.owner emitErrorCode:@"permissionDenied"
                                  message:@"Camera access was not granted"];
        }
      });
    }];
    return;
  }
  if (!_permissionDenied) {
    _permissionDenied = YES;
    [self updateState:@"stopped"];
    [self.owner emitErrorCode:@"permissionDenied"
                      message:@"Camera access is denied"];
  }
}

- (void)configureAndStart {
  [self updateState:@"starting"];
  NSUInteger generation = ++_generation;
  NSString *lens = [_lens copy];
  __weak LynxCameraPreviewContainer *weakSelf = self;
  dispatch_async(_sessionQueue, ^{
    LynxCameraPreviewContainer *strongSelf = weakSelf;
    if (strongSelf == nil || generation != strongSelf->_generation) {
      return;
    }
    NSError *error = nil;
    BOOL configured = [strongSelf configureSessionForLens:lens error:&error];
    if (configured && generation == strongSelf->_generation &&
        !strongSelf->_session.isRunning) {
      [strongSelf->_session startRunning];
    }
    dispatch_async(dispatch_get_main_queue(), ^{
      LynxCameraPreviewContainer *mainSelf = weakSelf;
      if (mainSelf == nil || generation != mainSelf->_generation ||
          !mainSelf.isCameraActive || mainSelf.window == nil) {
        return;
      }
      if (!configured) {
        [mainSelf updateState:@"stopped"];
        [mainSelf.owner emitErrorCode:@"configurationFailed"
                              message:error.localizedDescription ?:
                                          @"Unable to configure the camera"];
        return;
      }
      [mainSelf updateState:@"ready"];
      [mainSelf emitReady];
    });
  });
}

- (BOOL)configureSessionForLens:(NSString *)lens error:(NSError **)error {
  AVCaptureDevicePosition position = [lens isEqualToString:@"front"]
                                         ? AVCaptureDevicePositionFront
                                         : AVCaptureDevicePositionBack;
  AVCaptureDevice *device = [AVCaptureDevice
      defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera
                        mediaType:AVMediaTypeVideo
                         position:position];
  if (device == nil) {
    if (error != NULL) {
      *error = [NSError errorWithDomain:@"LynxCamera"
                                   code:10
                               userInfo:@{NSLocalizedDescriptionKey :
                                            @"The selected camera is unavailable"}];
    }
    return NO;
  }
  AVCaptureDeviceInput *input =
      [AVCaptureDeviceInput deviceInputWithDevice:device error:error];
  if (input == nil) {
    return NO;
  }
  AVCapturePhotoOutput *output = [[AVCapturePhotoOutput alloc] init];

  [_session beginConfiguration];
  for (AVCaptureInput *existing in _session.inputs) {
    [_session removeInput:existing];
  }
  for (AVCaptureOutput *existing in _session.outputs) {
    [_session removeOutput:existing];
  }
  if ([_session canSetSessionPreset:AVCaptureSessionPresetPhoto]) {
    _session.sessionPreset = AVCaptureSessionPresetPhoto;
  }
  if (![_session canAddInput:input] || ![_session canAddOutput:output]) {
    [_session commitConfiguration];
    if (error != NULL) {
      *error = [NSError errorWithDomain:@"LynxCamera"
                                   code:11
                               userInfo:@{NSLocalizedDescriptionKey :
                                            @"The selected camera configuration is unsupported"}];
    }
    return NO;
  }
  [_session addInput:input];
  [_session addOutput:output];
  [_session commitConfiguration];

  _device = device;
  _deviceInput = input;
  _photoOutput = output;
  [self applyControlsOnSessionQueue];
  return YES;
}

- (void)reconfigureIfRunning {
  if (self.isCameraActive && self.window != nil &&
      [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo] ==
          AVAuthorizationStatusAuthorized) {
    [self configureAndStart];
  }
}

- (void)stopCamera {
  [self updateState:@"stopped"];
  ++_generation;
  __weak LynxCameraPreviewContainer *weakSelf = self;
  dispatch_async(_sessionQueue, ^{
    LynxCameraPreviewContainer *strongSelf = weakSelf;
    if (strongSelf != nil && strongSelf->_session.isRunning) {
      [strongSelf->_session stopRunning];
    }
  });
}

- (void)applyControls {
  __weak LynxCameraPreviewContainer *weakSelf = self;
  dispatch_async(_sessionQueue, ^{
    [weakSelf applyControlsOnSessionQueue];
  });
}

- (void)applyControlsOnSessionQueue {
  AVCaptureDevice *device = _device;
  if (device == nil) {
    return;
  }
  NSError *error = nil;
  if (![device lockForConfiguration:&error]) {
    return;
  }
  CGFloat maxZoom = MIN(device.activeFormat.videoMaxZoomFactor,
                        device.maxAvailableVideoZoomFactor);
  CGFloat minZoom = MAX(1.0, device.minAvailableVideoZoomFactor);
  device.videoZoomFactor = MAX(minZoom, MIN(maxZoom, _requestedZoom));
  if (device.hasTorch) {
    device.torchMode = _torchEnabled ? AVCaptureTorchModeOn
                                     : AVCaptureTorchModeOff;
  }
  CGFloat exposure = MAX(device.minExposureTargetBias,
                         MIN(device.maxExposureTargetBias,
                             _exposureCompensation));
  [device setExposureTargetBias:exposure completionHandler:nil];
  [device unlockForConfiguration];
}

- (void)captureWithCompletion:(LynxCameraCaptureCompletion)completion {
  if (![_state isEqualToString:@"ready"] || _photoOutput == nil) {
    completion(nil, @"Camera is not ready");
    return;
  }
  if (_captureCompletion != nil) {
    completion(nil, @"A photo capture is already in progress");
    return;
  }
  _captureCompletion = [completion copy];
  _captureMirror = _mirrorPhoto && [_lens isEqualToString:@"front"];
  AVCaptureVideoOrientation orientation = [self currentVideoOrientation];
  __weak LynxCameraPreviewContainer *weakSelf = self;
  dispatch_async(_sessionQueue, ^{
    LynxCameraPreviewContainer *strongSelf = weakSelf;
    if (strongSelf == nil || strongSelf->_photoOutput == nil) {
      dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf finishCaptureWithPhoto:nil errorMessage:@"Camera is not ready"];
      });
      return;
    }
    NSDictionary *format = [strongSelf->_photoOutput.availablePhotoCodecTypes
            containsObject:AVVideoCodecTypeJPEG]
        ? @{ AVVideoCodecKey : AVVideoCodecTypeJPEG }
        : nil;
    AVCapturePhotoSettings *settings = format == nil
                                           ? [AVCapturePhotoSettings photoSettings]
                                           : [AVCapturePhotoSettings
                                                 photoSettingsWithFormat:format];
    if ([strongSelf->_photoOutput.supportedFlashModes
            containsObject:@(strongSelf.flashMode)]) {
      settings.flashMode = strongSelf.flashMode;
    }
    settings.photoQualityPrioritization = AVCapturePhotoQualityPrioritizationSpeed;
    AVCaptureConnection *connection =
        [strongSelf->_photoOutput connectionWithMediaType:AVMediaTypeVideo];
    if (connection.isVideoOrientationSupported) {
      connection.videoOrientation = orientation;
    }
    [strongSelf->_photoOutput capturePhotoWithSettings:settings
                                              delegate:strongSelf];
  });
}

- (void)captureOutput:(AVCapturePhotoOutput *)output
    didFinishProcessingPhoto:(AVCapturePhoto *)photo
                       error:(nullable NSError *)error {
  NSData *data = error == nil ? photo.fileDataRepresentation : nil;
  UIImage *image = data == nil ? nil : [UIImage imageWithData:data];
  NSError *writeError = error;
  NSDictionary *result = image == nil
                             ? nil
                             : LynxCameraWriteJPEG(
                                   image,
                                   _photoQuality / 100.0,
                                   _captureMirror,
                                   &writeError);
  NSString *message = result == nil
                          ? (writeError.localizedDescription ?:
                                 @"Unable to capture a photo")
                          : nil;
  dispatch_async(dispatch_get_main_queue(), ^{
    [self finishCaptureWithPhoto:result errorMessage:message];
  });
}

- (void)finishCaptureWithPhoto:(nullable NSDictionary *)photo
                   errorMessage:(nullable NSString *)message {
  LynxCameraCaptureCompletion completion = _captureCompletion;
  _captureCompletion = nil;
  if (photo != nil) {
    [self.owner emitCapture:photo];
  } else {
    [self.owner emitErrorCode:@"captureFailed"
                      message:message ?: @"Unable to capture a photo"];
  }
  if (completion != nil) {
    completion(photo, message);
  }
}

- (void)focusAtNormalizedPoint:(CGPoint)point
                    completion:(LynxCameraOperationCompletion)completion {
  if (![_state isEqualToString:@"ready"] || _device == nil ||
      self.bounds.size.width <= 0 || self.bounds.size.height <= 0) {
    completion(@"Camera is not ready");
    return;
  }
  CGPoint viewPoint = CGPointMake(point.x * self.bounds.size.width,
                                  point.y * self.bounds.size.height);
  CGPoint devicePoint =
      [_previewLayer captureDevicePointOfInterestForPoint:viewPoint];
  __weak LynxCameraPreviewContainer *weakSelf = self;
  dispatch_async(_sessionQueue, ^{
    LynxCameraPreviewContainer *strongSelf = weakSelf;
    if (strongSelf == nil) {
      dispatch_async(dispatch_get_main_queue(), ^{
        completion(@"Camera view was released");
      });
      return;
    }
    AVCaptureDevice *device = strongSelf->_device;
    NSError *error = nil;
    if (device == nil || ![device lockForConfiguration:&error]) {
      dispatch_async(dispatch_get_main_queue(), ^{
        completion(error.localizedDescription ?: @"Unable to focus the camera");
      });
      return;
    }
    if (device.isFocusPointOfInterestSupported &&
        [device isFocusModeSupported:AVCaptureFocusModeAutoFocus]) {
      device.focusPointOfInterest = devicePoint;
      device.focusMode = AVCaptureFocusModeAutoFocus;
    }
    if (device.isExposurePointOfInterestSupported &&
        [device isExposureModeSupported:AVCaptureExposureModeContinuousAutoExposure]) {
      device.exposurePointOfInterest = devicePoint;
      device.exposureMode = AVCaptureExposureModeContinuousAutoExposure;
    }
    [device unlockForConfiguration];
    dispatch_async(dispatch_get_main_queue(), ^{
      completion(nil);
    });
  });
}

- (void)emitReady {
  AVCaptureDevice *device = _device;
  if (device == nil) {
    return;
  }
  CGFloat minZoom = MAX(1.0, device.minAvailableVideoZoomFactor);
  CGFloat maxZoom = MIN(device.activeFormat.videoMaxZoomFactor,
                        device.maxAvailableVideoZoomFactor);
  [self.owner emitReady:@{
    @"lens" : _lens,
    @"zoom" : @(device.videoZoomFactor),
    @"minZoom" : @(minZoom),
    @"maxZoom" : @(maxZoom),
    @"torchSupported" : @(device.hasTorch),
    @"exposureMin" : @(device.minExposureTargetBias),
    @"exposureMax" : @(device.maxExposureTargetBias),
  }];
}

- (void)updateState:(NSString *)state {
  if ([_state isEqualToString:state]) {
    return;
  }
  _state = [state copy];
  [self.owner emitState:state];
}

- (AVCaptureVideoOrientation)currentVideoOrientation {
  UIInterfaceOrientation orientation = self.window.windowScene.interfaceOrientation;
  switch (orientation) {
    case UIInterfaceOrientationLandscapeLeft:
      return AVCaptureVideoOrientationLandscapeLeft;
    case UIInterfaceOrientationLandscapeRight:
      return AVCaptureVideoOrientationLandscapeRight;
    case UIInterfaceOrientationPortraitUpsideDown:
      return AVCaptureVideoOrientationPortraitUpsideDown;
    case UIInterfaceOrientationPortrait:
    case UIInterfaceOrientationUnknown:
    default:
      return AVCaptureVideoOrientationPortrait;
  }
}

- (void)dispose {
  _cameraActive = NO;
  _captureCompletion = nil;
  [self stopCamera];
  self.owner = nil;
}

@end

@LynxElement("x-camera-view")
@implementation LynxUICameraView

- (LynxCameraPreviewContainer *)createView {
  LynxCameraPreviewContainer *container =
      [[LynxCameraPreviewContainer alloc] init];
  container.owner = self;
  return container;
}

LYNX_PROP_SETTER("active", setActive, BOOL) {
  self.view.cameraActive = requestReset ? YES : value;
}

LYNX_PROP_SETTER("lens", setLens, NSString *) {
  self.view.lens = requestReset ? @"back" : value;
}

LYNX_PROP_SETTER("zoom", setZoom, CGFloat) {
  self.view.requestedZoom = requestReset ? 1.0 : value;
}

LYNX_PROP_SETTER("torch", setTorch, NSString *) {
  self.view.torchEnabled = !requestReset && [value isEqualToString:@"on"];
}

LYNX_PROP_SETTER("flash", setFlash, NSString *) {
  if (requestReset || [value isEqualToString:@"auto"]) {
    self.view.flashMode = AVCaptureFlashModeAuto;
  } else if ([value isEqualToString:@"on"]) {
    self.view.flashMode = AVCaptureFlashModeOn;
  } else {
    self.view.flashMode = AVCaptureFlashModeOff;
  }
}

LYNX_PROP_SETTER("exposure-compensation", setExposureCompensation, CGFloat) {
  self.view.exposureCompensation = requestReset ? 0 : value;
}

LYNX_PROP_SETTER("photo-quality", setPhotoQuality, NSInteger) {
  self.view.photoQuality = requestReset ? 92 : value;
}

LYNX_PROP_SETTER("mirror-photo", setMirrorPhoto, BOOL) {
  self.view.mirrorPhoto = requestReset ? YES : value;
}

LYNX_PROP_SETTER("preview-fit", setPreviewFit, NSString *) {
  [self.view setPreviewFit:requestReset ? @"cover" : value];
}

LYNX_UI_METHOD(capture) {
  [self.view captureWithCompletion:^(NSDictionary *photo, NSString *message) {
    if (photo != nil) {
      callback(kUIMethodSuccess, photo);
    } else {
      callback(kUIMethodInvalidStateError,
               message ?: @"Unable to capture a photo");
    }
  }];
}

LYNX_UI_METHOD(focusAtPoint) {
  NSNumber *x = [params[@"x"] isKindOfClass:NSNumber.class]
                    ? params[@"x"]
                    : nil;
  NSNumber *y = [params[@"y"] isKindOfClass:NSNumber.class]
                    ? params[@"y"]
                    : nil;
  if (x == nil || y == nil || !isfinite(x.doubleValue) ||
      !isfinite(y.doubleValue) || x.doubleValue < 0 || x.doubleValue > 1 ||
      y.doubleValue < 0 || y.doubleValue > 1) {
    callback(kUIMethodParamInvalid,
             @"Camera focus coordinates must be in [0, 1]");
    return;
  }
  [self.view focusAtNormalizedPoint:CGPointMake(x.doubleValue, y.doubleValue)
                          completion:^(NSString *message) {
    if (message == nil) {
      callback(kUIMethodSuccess, @{});
    } else {
      callback(kUIMethodInvalidStateError, message);
    }
  }];
}

- (void)emitReady:(NSDictionary *)detail {
  [self emitEvent:@"ready" detail:detail];
}

- (void)emitState:(NSString *)state {
  [self emitEvent:@"statechange" detail:@{ @"state" : state }];
}

- (void)emitErrorCode:(NSString *)code message:(NSString *)message {
  [self emitEvent:@"error"
           detail:@{ @"code" : code, @"message" : message ?: @"" }];
}

- (void)emitCapture:(NSDictionary *)photo {
  [self emitEvent:@"capture" detail:@{ @"photo" : photo }];
}

- (void)emitEvent:(NSString *)name detail:(NSDictionary *)detail {
  LynxDetailEvent *event =
      [[LynxDetailEvent alloc] initWithName:name
                                targetSign:self.sign
                                    detail:detail];
  [self.context.eventEmitter dispatchCustomEvent:event];
}

- (void)dealloc {
  [self.view dispose];
}

@end
