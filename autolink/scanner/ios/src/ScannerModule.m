#import "ScannerModule.h"

#import <AVFoundation/AVFoundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <ImageIO/ImageIO.h>
#import <Lynx/LynxContext.h>
#import <UIKit/UIKit.h>
#import <Vision/Vision.h>

static NSString *const kOutcomeSuccess = @"success";
static NSString *const kOutcomeUserCancel = @"userCancel";
static NSString *const kOutcomePermissionDenied = @"permissionDenied";
static NSString *const kOutcomeUnavailable = @"unavailable";
static NSString *const kOutcomeBusy = @"busy";
static NSString *const kOutcomeNoCodeFound = @"noCodeFound";

/** Full-screen AVFoundation scanner presented by the module. */
@interface LynxScannerViewController : UIViewController
    <AVCaptureMetadataOutputObjectsDelegate>
@property (nonatomic, copy)
    void (^onResult)(NSString *code, NSString *_Nullable content,
                     NSString *_Nullable format, NSString *message);
@end

/** Dims everything outside the centered frame and draws corner brackets. */
@interface LynxScannerOverlayView : UIView
@property (nonatomic, strong, nullable) UIView *hintLabel;
@end

// Exported to Lynx as `Scanner`.
@LynxNativeModule("Scanner")
@implementation ScannerModule {
  LynxContext *_context;
  LynxCallbackBlock _callback;
  LynxScannerViewController *_scannerController;
}

+ (NSString *)name {
  return @"Scanner";
}

+ (NSDictionary<NSString *, NSString *> *)methodLookup {
  return @{
    @"scan" : NSStringFromSelector(@selector(scan:)),
    @"scanFromImage" : NSStringFromSelector(@selector(scanFromImage:callback:)),
  };
}

- (instancetype)initWithLynxContext:(LynxContext *)context {
  self = [super init];
  if (self) {
    _context = context;
  }
  return self;
}

- (void)scan:(LynxCallbackBlock)callback {
  dispatch_async(dispatch_get_main_queue(), ^{
    if (self->_callback != nil) {
      callback([self outcomeJSONWithCode:kOutcomeBusy
                                 content:nil
                                  format:nil
                                 message:@"Another scanner request is already active"]);
      return;
    }
    if ([self cameraCount] == 0) {
      callback([self outcomeJSONWithCode:kOutcomeUnavailable
                                 content:nil
                                  format:nil
                                 message:@"This device has no camera"]);
      return;
    }
    self->_callback = [callback copy];
    AVAuthorizationStatus status =
        [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    if (status == AVAuthorizationStatusAuthorized) {
      [self presentScanner];
      return;
    }
    if (status == AVAuthorizationStatusNotDetermined) {
      __weak ScannerModule *weakSelf = self;
      [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo
                               completionHandler:^(BOOL granted) {
        dispatch_async(dispatch_get_main_queue(), ^{
          ScannerModule *strongSelf = weakSelf;
          if (strongSelf == nil || strongSelf->_callback == nil) {
            return;
          }
          if (granted) {
            [strongSelf presentScanner];
          } else {
            [strongSelf finishWithCode:kOutcomePermissionDenied
                                content:nil
                                 format:nil
                                message:@"Camera access was not granted"];
          }
        });
      }];
      return;
    }
    [self finishWithCode:kOutcomePermissionDenied
                 content:nil
                  format:nil
                 message:@"Camera access is denied"];
  });
}

- (void)scanFromImage:(NSString *)uri callback:(LynxCallbackBlock)callback {
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    NSString *trimmed = [uri stringByTrimmingCharactersInSet:
        NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) {
      callback([self errorJSON:@"Image URI must not be empty"]);
      return;
    }
    NSURL *url = [NSURL URLWithString:trimmed];
    if (url == nil || !url.fileURL) {
      callback([self errorJSON:@"Scanner reads file:// image URIs on iOS"]);
      return;
    }

    CGImageSourceRef source = CGImageSourceCreateWithURL(
        (__bridge CFURLRef)url, nil);
    CGImageRef cgImage = source != NULL
        ? CGImageSourceCreateImageAtIndex(source, 0, nil)
        : NULL;
    if (source != NULL) {
      CFRelease(source);
    }
    if (cgImage == NULL) {
      callback([self errorJSON:@"Unable to read the image file"]);
      return;
    }

    NSNumber *orientationNumber = [self imageOrientationAtURL:url];
    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc]
        initWithCGImage:cgImage
            orientation:(orientationNumber != nil
                            ? (CGImagePropertyOrientation)orientationNumber
                                  .unsignedIntValue
                            : kCGImagePropertyOrientationUp)
                options:@{}];
    VNDetectBarcodesRequest *request =
        [[VNDetectBarcodesRequest alloc] initWithCompletionHandler:nil];
    NSMutableArray<NSString *> *symbologies = [NSMutableArray arrayWithArray:@[
      VNBarcodeSymbologyQR, VNBarcodeSymbologyAztec, VNBarcodeSymbologyCode39,
      VNBarcodeSymbologyCode39Checksum, VNBarcodeSymbologyCode93,
      VNBarcodeSymbologyCode128, VNBarcodeSymbologyDataMatrix,
      VNBarcodeSymbologyEAN8, VNBarcodeSymbologyEAN13, VNBarcodeSymbologyI2of5,
      VNBarcodeSymbologyITF14, VNBarcodeSymbologyPDF417, VNBarcodeSymbologyUPCE
    ]];
    if (@available(iOS 15.0, *)) {
      [symbologies addObject:VNBarcodeSymbologyCodabar];
    }
    request.symbologies = symbologies;
    NSError *requestError = nil;
    BOOL performed = [handler performRequests:@[ request ] error:&requestError];
    CGImageRelease(cgImage);
    dispatch_async(dispatch_get_main_queue(), ^{
      if (!performed) {
        callback([self errorJSON:requestError.localizedDescription ?:
                              @"Unable to decode the image"]);
        return;
      }
      VNBarcodeObservation *first = nil;
      for (VNBarcodeObservation *observation in request.results) {
        if (![observation isKindOfClass:VNBarcodeObservation.class]) {
          continue;
        }
        if (observation.payloadStringValue.length > 0) {
          first = observation;
          break;
        }
      }
      if (first == nil) {
        callback([self outcomeJSONWithCode:kOutcomeNoCodeFound
                                   content:nil
                                    format:nil
                                   message:@"No code was found in the image"]);
        return;
      }
      callback([self outcomeJSONWithCode:kOutcomeSuccess
                                   content:first.payloadStringValue
                                    format:[ScannerModule
                                        formatOfVisionSymbology:first.symbology]
                                   message:@""]);
    });
  });
}

- (void)destroy {
  dispatch_async(dispatch_get_main_queue(), ^{
    self->_callback = nil;
    [self->_scannerController dismissViewControllerAnimated:NO completion:nil];
    self->_scannerController = nil;
  });
}

#pragma mark - Scanning UI

- (NSUInteger)cameraCount {
  AVCaptureDeviceDiscoverySession *session =
      [AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:@[
        AVCaptureDeviceTypeBuiltInWideAngleCamera
      ]
                                                              mediaType:AVMediaTypeVideo
                                                               position:AVCaptureDevicePositionUnspecified];
  return session.devices.count;
}

- (void)presentScanner {
  UIViewController *presenter = [self presentingViewController];
  if (presenter == nil) {
    [self finishWithCode:kOutcomeUnavailable
                 content:nil
                  format:nil
                 message:@"Unable to find a view controller for the scanner"];
    return;
  }
  LynxScannerViewController *controller = [[LynxScannerViewController alloc] init];
  __weak ScannerModule *weakSelf = self;
  controller.onResult = ^(NSString *code,
                          NSString *content,
                          NSString *format,
                          NSString *message) {
    ScannerModule *strongSelf = weakSelf;
    if (strongSelf == nil) {
      return;
    }
    [strongSelf finishWithCode:code content:content format:format message:message];
  };
  _scannerController = controller;
  controller.modalPresentationStyle = UIModalPresentationFullScreen;
  [presenter presentViewController:controller animated:YES completion:nil];
}

- (nullable UIViewController *)presentingViewController {
  UIViewController *root = _context.getLynxView.window.rootViewController;
  if (root == nil) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
      if (![scene isKindOfClass:UIWindowScene.class]) {
        continue;
      }
      for (UIWindow *window in ((UIWindowScene *)scene).windows) {
        if (window.isKeyWindow) {
          root = window.rootViewController;
          break;
        }
      }
      if (root != nil) {
        break;
      }
    }
  }
  return [self topViewController:root];
}

- (nullable UIViewController *)topViewController:(nullable UIViewController *)controller {
  if (controller.presentedViewController != nil) {
    return [self topViewController:controller.presentedViewController];
  }
  if ([controller isKindOfClass:UINavigationController.class]) {
    return [self topViewController:((UINavigationController *)controller).visibleViewController];
  }
  if ([controller isKindOfClass:UITabBarController.class]) {
    return [self topViewController:((UITabBarController *)controller).selectedViewController];
  }
  return controller;
}

- (void)finishWithCode:(NSString *)code
               content:(nullable NSString *)content
                format:(nullable NSString *)format
               message:(NSString *)message {
  LynxCallbackBlock callback = _callback;
  _callback = nil;
  if (callback != nil) {
    callback([self outcomeJSONWithCode:code content:content format:format message:message]);
  }
}

#pragma mark - Image decoding

- (NSNumber *)imageOrientationAtURL:(NSURL *)url {
  CGImageSourceRef source = CGImageSourceCreateWithURL(
      (__bridge CFURLRef)url, nil);
  if (source == NULL) {
    return nil;
  }
  CFDictionaryRef properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil);
  CFRelease(source);
  if (properties == NULL) {
    return nil;
  }
  NSNumber *orientation = CFBridgingRelease(
      CFDictionaryGetValue(properties, kCGImagePropertyOrientation));
  CFRelease(properties);
  return orientation;
}

+ (NSString *)formatOfVisionSymbology:(VNBarcodeSymbology)symbology {
  if ([symbology isEqualToString:VNBarcodeSymbologyQR]) {
    return @"qr_code";
  }
  if ([symbology isEqualToString:VNBarcodeSymbologyAztec]) {
    return @"aztec";
  }
  if (@available(iOS 15.0, *)
      && [symbology isEqualToString:VNBarcodeSymbologyCodabar]) {
    return @"codabar";
  }
  if ([symbology isEqualToString:VNBarcodeSymbologyCode39]
      || [symbology isEqualToString:VNBarcodeSymbologyCode39Checksum]) {
    return @"code39";
  }
  if ([symbology isEqualToString:VNBarcodeSymbologyCode93]) {
    return @"code93";
  }
  if ([symbology isEqualToString:VNBarcodeSymbologyCode128]) {
    return @"code128";
  }
  if ([symbology isEqualToString:VNBarcodeSymbologyDataMatrix]) {
    return @"data_matrix";
  }
  if ([symbology isEqualToString:VNBarcodeSymbologyEAN8]) {
    return @"ean_8";
  }
  if ([symbology isEqualToString:VNBarcodeSymbologyEAN13]) {
    return @"ean_13";
  }
  if ([symbology isEqualToString:VNBarcodeSymbologyI2of5]
      || [symbology isEqualToString:VNBarcodeSymbologyITF14]) {
    return @"itf";
  }
  if ([symbology isEqualToString:VNBarcodeSymbologyPDF417]) {
    return @"pdf417";
  }
  if ([symbology isEqualToString:VNBarcodeSymbologyUPCE]) {
    return @"upc_e";
  }
  return @"unknown";
}

#pragma mark - JSON encoding

- (NSString *)outcomeJSONWithCode:(NSString *)code
                          content:(nullable NSString *)content
                           format:(nullable NSString *)format
                          message:(NSString *)message {
  NSData *data = [NSJSONSerialization dataWithJSONObject:@{
    @"error" : @"",
    @"value" : @{
      @"code" : code,
      @"content" : content ?: NSNull.null,
      @"format" : format ?: NSNull.null,
      @"message" : message ?: @"",
    },
  } options:0 error:nil];
  if (data == nil) {
    return [self errorJSON:@"Unable to encode scanner result"];
  }
  return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

- (NSString *)errorJSON:(NSString *)message {
  NSData *data = [NSJSONSerialization dataWithJSONObject:@{
    @"error" : message,
  } options:0 error:nil];
  if (data == nil) {
    return @"{\"error\":\"Unable to encode scanner result\"}";
  }
  return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

@end

#pragma mark - Scanner view controller

@implementation LynxScannerViewController {
  AVCaptureSession *_session;
  AVCaptureVideoPreviewLayer *_previewLayer;
  LynxScannerOverlayView *_overlayView;
  UILabel *_hintLabel;
  UIButton *_closeButton;
  dispatch_queue_t _sessionQueue;
  BOOL _delivered;
}

- (void)viewDidLoad {
  [super viewDidLoad];
  self.view.backgroundColor = UIColor.blackColor;
  self.modalPresentationCapturesStatusBarAppearance = YES;

  _sessionQueue = dispatch_queue_create("lynx.scanner.session", DISPATCH_QUEUE_SERIAL);

  _previewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:nil];
  _previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
  _previewLayer.frame = self.view.bounds;
  [self.view.layer addSublayer:_previewLayer];

  _overlayView = [[LynxScannerOverlayView alloc] initWithFrame:self.view.bounds];
  _overlayView.autoresizingMask = UIViewAutoresizingFlexibleWidth
      | UIViewAutoresizingFlexibleHeight;
  [self.view addSubview:_overlayView];

  _hintLabel = [[UILabel alloc] init];
  _hintLabel.text = @"Align the code inside the frame";
  _hintLabel.textColor = [UIColor colorWithWhite:1 alpha:0.9];
  _hintLabel.font = [UIFont systemFontOfSize:14];
  _hintLabel.textAlignment = NSTextAlignmentCenter;
  _hintLabel.adjustsFontForContentSizeCategory = YES;
  [_overlayView addSubview:_hintLabel];
  _overlayView.hintLabel = _hintLabel;

  _closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
  [_closeButton setTitle:@"✕" forState:UIControlStateNormal];
  [_closeButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
  _closeButton.titleLabel.font = [UIFont systemFontOfSize:20];
  _closeButton.backgroundColor =
      [UIColor colorWithWhite:0 alpha:0.2];
  _closeButton.layer.cornerRadius = 22;
  _closeButton.clipsToBounds = YES;
  [_closeButton addTarget:self
                   action:@selector(closeTapped)
         forControlEvents:UIControlEventTouchUpInside];
  [self.view addSubview:_closeButton];
}

- (void)viewDidLayoutSubviews {
  [super viewDidLayoutSubviews];
  _previewLayer.frame = self.view.bounds;
  CGFloat side = 44;
  _closeButton.frame = CGRectMake(16,
                                  self.view.safeAreaInsets.top + 8,
                                  side,
                                  side);
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
  if (_previewLayer.connection.isVideoOrientationSupported) {
    _previewLayer.connection.videoOrientation = AVCaptureVideoOrientationPortrait;
  }
#pragma clang diagnostic pop
}

- (void)viewWillAppear:(BOOL)animated {
  [super viewWillAppear:animated];
  [self configureSessionIfNeeded];
  [self setNeedsStatusBarAppearanceUpdate];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
  return UIStatusBarStyleLightContent;
}

- (void)closeTapped {
  [self deliverCode:kOutcomeUserCancel content:nil format:nil message:@""];
}

- (void)configureSessionIfNeeded {
  __weak LynxScannerViewController *weakSelf = self;
  dispatch_async(_sessionQueue, ^{
    LynxScannerViewController *strongSelf = weakSelf;
    if (strongSelf == nil || strongSelf->_delivered) {
      return;
    }
    if (strongSelf->_session != nil) {
      [strongSelf->_session startRunning];
      return;
    }
    AVCaptureSession *session = [[AVCaptureSession alloc] init];
    session.sessionPreset = AVCaptureSessionPresetHigh;
    NSError *error = nil;
    AVCaptureDevice *device = [AVCaptureDevice
        defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera
                           mediaType:AVMediaTypeVideo
                            position:AVCaptureDevicePositionBack];
    AVCaptureDeviceInput *input =
        device != nil ? [AVCaptureDeviceInput deviceInputWithDevice:device
                                                              error:&error]
                      : nil;
    AVCaptureMetadataOutput *metadataOutput = [[AVCaptureMetadataOutput alloc] init];
    if (input == nil || ![session canAddInput:input]
        || ![session canAddOutput:metadataOutput]) {
      dispatch_async(dispatch_get_main_queue(), ^{
        [strongSelf deliverCode:kOutcomeUnavailable
                        content:nil
                         format:nil
                        message:(error != nil ? error.localizedDescription
                                               : @"The camera is unavailable")];
      });
      return;
    }
    [session addInput:input];
    [session addOutput:metadataOutput];
    [metadataOutput setMetadataObjectsDelegate:strongSelf
                                           queue:dispatch_get_main_queue()];
    NSArray<AVMetadataObjectType> *wanted = @[
      AVMetadataObjectTypeQRCode, AVMetadataObjectTypeAztecCode,
      AVMetadataObjectTypeCode39Code, AVMetadataObjectTypeCode39Mod43Code,
      AVMetadataObjectTypeCode93Code, AVMetadataObjectTypeCode128Code,
      AVMetadataObjectTypeDataMatrixCode, AVMetadataObjectTypeEAN8Code,
      AVMetadataObjectTypeEAN13Code, AVMetadataObjectTypeInterleaved2of5Code,
      AVMetadataObjectTypeITF14Code, AVMetadataObjectTypePDF417Code,
      AVMetadataObjectTypeUPCECode
    ];
    NSMutableArray<AVMetadataObjectType> *supported = [NSMutableArray array];
    for (AVMetadataObjectType type in metadataOutput.availableMetadataObjectTypes) {
      if ([wanted containsObject:type]) {
        [supported addObject:type];
      }
    }
    if (@available(iOS 15.4, *)) {
      if ([metadataOutput.availableMetadataObjectTypes
              containsObject:AVMetadataObjectTypeCodabarCode]) {
        [supported addObject:AVMetadataObjectTypeCodabarCode];
      }
    }
    metadataOutput.metadataObjectTypes = supported;
    [strongSelf applyPortraitOrientationToOutput:metadataOutput];

    strongSelf->_session = session;
    strongSelf->_previewLayer.session = session;
    [session startRunning];
  });
}

// AVCaptureVideoOrientation is deprecated in iOS 17 in favor of
// videoRotationAngle, but the deployment target is iOS 13, so the classic
// orientation API is the only option available on every supported device.
- (void)applyPortraitOrientationToOutput:(AVCaptureMetadataOutput *)output {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
  AVCaptureConnection *connection =
      [output connectionWithMediaType:AVMediaTypeVideo];
  if (connection != nil && connection.isVideoOrientationSupported) {
    connection.videoOrientation = AVCaptureVideoOrientationPortrait;
  }
#pragma clang diagnostic pop
}

- (void)captureOutput:(AVCaptureOutput *)output
    didOutputMetadataObjects:(NSArray<AVMetadataObject *> *)metadataObjects
           fromConnection:(AVCaptureConnection *)connection {
  for (AVMetadataObject *object in metadataObjects) {
    if (![object isKindOfClass:AVMetadataMachineReadableCodeObject.class]) {
      continue;
    }
    AVMetadataMachineReadableCodeObject *code =
        (AVMetadataMachineReadableCodeObject *)object;
    if (code.stringValue.length == 0) {
      continue;
    }
    [self deliverCode:kOutcomeSuccess
              content:code.stringValue
               format:[LynxScannerViewController formatOfType:code.type]
               message:@""];
    return;
  }
}

+ (NSString *)formatOfType:(AVMetadataObjectType)type {
  if ([type isEqualToString:AVMetadataObjectTypeQRCode]) {
    return @"qr_code";
  }
  if ([type isEqualToString:AVMetadataObjectTypeAztecCode]) {
    return @"aztec";
  }
  if (@available(iOS 15.4, *)
      && [type isEqualToString:AVMetadataObjectTypeCodabarCode]) {
    return @"codabar";
  }
  if ([type isEqualToString:AVMetadataObjectTypeCode39Code]
      || [type isEqualToString:AVMetadataObjectTypeCode39Mod43Code]) {
    return @"code39";
  }
  if ([type isEqualToString:AVMetadataObjectTypeCode93Code]) {
    return @"code93";
  }
  if ([type isEqualToString:AVMetadataObjectTypeCode128Code]) {
    return @"code128";
  }
  if ([type isEqualToString:AVMetadataObjectTypeDataMatrixCode]) {
    return @"data_matrix";
  }
  if ([type isEqualToString:AVMetadataObjectTypeEAN8Code]) {
    return @"ean_8";
  }
  if ([type isEqualToString:AVMetadataObjectTypeEAN13Code]) {
    return @"ean_13";
  }
  if ([type isEqualToString:AVMetadataObjectTypeInterleaved2of5Code]
      || [type isEqualToString:AVMetadataObjectTypeITF14Code]) {
    return @"itf";
  }
  if ([type isEqualToString:AVMetadataObjectTypePDF417Code]) {
    return @"pdf417";
  }
  if ([type isEqualToString:AVMetadataObjectTypeUPCECode]) {
    return @"upc_e";
  }
  return @"unknown";
}

- (void)deliverCode:(NSString *)code
            content:(nullable NSString *)content
             format:(nullable NSString *)format
             message:(NSString *)message {
  dispatch_async(dispatch_get_main_queue(), ^{
    if (self->_delivered) {
      return;
    }
    self->_delivered = YES;
    dispatch_async(self->_sessionQueue, ^{
      [self->_session stopRunning];
    });
    void (^onResult)(NSString *, NSString *, NSString *, NSString *) =
        self.onResult;
    [self dismissViewControllerAnimated:YES completion:^{
      if (onResult != nil) {
        onResult(code, content, format, message);
      }
    }];
  });
}

- (void)dealloc {
  // Capture the ivars into locals: the block must not touch `self`, which is
  // already deallocating when it runs.
  AVCaptureSession *session = _session;
  dispatch_queue_t queue = _sessionQueue;
  if (session != nil && queue != nil) {
    dispatch_async(queue, ^{
      [session stopRunning];
    });
  }
}

@end

@implementation LynxScannerOverlayView {
  CAShapeLayer *_dimLayer;
  CAShapeLayer *_frameLayer;
}

- (instancetype)initWithFrame:(CGRect)frame {
  self = [super initWithFrame:frame];
  if (self) {
    self.backgroundColor = UIColor.clearColor;
    _dimLayer = [CAShapeLayer layer];
    _dimLayer.fillColor = [UIColor colorWithWhite:0 alpha:0.6].CGColor;
    _dimLayer.fillRule = kCAFillRuleEvenOdd;
    [self.layer addSublayer:_dimLayer];

    _frameLayer = [CAShapeLayer layer];
    _frameLayer.strokeColor = UIColor.whiteColor.CGColor;
    _frameLayer.fillColor = UIColor.clearColor.CGColor;
    _frameLayer.lineWidth = 4;
    _frameLayer.lineCap = kCALineCapSquare;
    [self.layer addSublayer:_frameLayer];
  }
  return self;
}

- (CGRect)frameRect {
  CGFloat width = self.bounds.size.width;
  CGFloat height = self.bounds.size.height;
  CGFloat side = MIN(width, height) * 0.62;
  CGFloat left = (width - side) / 2;
  CGFloat top = (height - side) * 0.4;
  return CGRectMake(left, top, side, side);
}

- (void)layoutSubviews {
  [super layoutSubviews];
  CGRect frame = [self frameRect];
  CGRect full = CGRectMake(0, 0, self.bounds.size.width, self.bounds.size.height);

  CGMutablePathRef dimPath = CGPathCreateMutable();
  CGPathAddRect(dimPath, NULL, full);
  CGPathAddRect(dimPath, NULL, frame);
  _dimLayer.path = CGPathCreateCopy(dimPath);
  CGPathRelease(dimPath);

  CGFloat corner = 24;
  CGMutablePathRef framePath = CGPathCreateMutable();
  CGPathMoveToPoint(framePath, NULL,
                    CGRectGetMinX(frame), CGRectGetMinY(frame) + corner);
  CGPathAddLineToPoint(framePath, NULL,
                       CGRectGetMinX(frame), CGRectGetMinY(frame));
  CGPathAddLineToPoint(framePath, NULL,
                       CGRectGetMinX(frame) + corner, CGRectGetMinY(frame));
  CGPathMoveToPoint(framePath, NULL,
                    CGRectGetMaxX(frame) - corner, CGRectGetMinY(frame));
  CGPathAddLineToPoint(framePath, NULL,
                       CGRectGetMaxX(frame), CGRectGetMinY(frame));
  CGPathAddLineToPoint(framePath, NULL,
                       CGRectGetMaxX(frame), CGRectGetMinY(frame) + corner);
  CGPathMoveToPoint(framePath, NULL,
                       CGRectGetMaxX(frame), CGRectGetMaxY(frame) - corner);
  CGPathAddLineToPoint(framePath, NULL,
                       CGRectGetMaxX(frame), CGRectGetMaxY(frame));
  CGPathAddLineToPoint(framePath, NULL,
                       CGRectGetMaxX(frame) - corner, CGRectGetMaxY(frame));
  CGPathMoveToPoint(framePath, NULL,
                       CGRectGetMinX(frame) + corner, CGRectGetMaxY(frame));
  CGPathAddLineToPoint(framePath, NULL,
                       CGRectGetMinX(frame), CGRectGetMaxY(frame));
  CGPathAddLineToPoint(framePath, NULL,
                       CGRectGetMinX(frame), CGRectGetMaxY(frame) - corner);
  _frameLayer.path = CGPathCreateCopy(framePath);
  CGPathRelease(framePath);

  if (self.hintLabel != nil) {
    self.hintLabel.frame = CGRectMake(0,
                                      CGRectGetMaxY(frame) + 28,
                                      self.bounds.size.width,
                                      20);
  }
}

@end
