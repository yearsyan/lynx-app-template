#import "DeviceModule.h"

#import <CoreLocation/CoreLocation.h>
#import <CoreMotion/CoreMotion.h>
#import <Lynx/LynxContext.h>
#import <Lynx/LynxView.h>
#import <sys/utsname.h>

static NSString *const LynxStatusBarStyleDarkContent = @"dark-content";
static NSString *const LynxStatusBarStyleLightContent = @"light-content";
static NSString *const kEventName = @"sensors";
static NSString *const kTypeAccelerometer = @"accelerometer";
static NSString *const kTypeCompass = @"compass";
static NSString *const kTypeGyroscope = @"gyroscope";
static NSString *const kTypeMagnetometer = @"magnetometer";
static NSString *const kTypeBarometer = @"barometer";
// Core Motion reports CMAcceleration in g; the public Device contract uses
// SI acceleration units on every platform.
static const double kStandardGravityMetersPerSecondSquared = 9.80665;

static NSString *LynxDeviceJSON(NSDictionary<NSString *, id> *result) {
  NSError *error = nil;
  NSData *data = [NSJSONSerialization dataWithJSONObject:result
                                                 options:0
                                                   error:&error];
  if (data == nil) {
    NSString *message = error.localizedDescription ?: @"serialization failed";
    NSDictionary<NSString *, id> *fallback = @{
      @"error" : [@"Device " stringByAppendingString:message],
    };
    data = [NSJSONSerialization dataWithJSONObject:fallback options:0 error:nil];
  }
  return data == nil
             ? @"{\"error\":\"Device serialization failed\"}"
             : [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

LynxTemplateData *LynxDeviceTemplateData(
    UIEdgeInsets insets,
    NSDictionary<NSString *, id> *_Nullable additionalData) {
  NSMutableDictionary<NSString *, id> *data =
      [NSMutableDictionary dictionaryWithDictionary:additionalData ?: @{}];
  NSMutableDictionary<NSString *, id> *nativeEnvironment =
      [NSMutableDictionary dictionaryWithDictionary:@{
    @"schemaVersion" : @2,
    @"unit" : @"px",
    @"safeAreaInsets" : @{
      @"top" : @(MAX(0, insets.top)),
      @"right" : @(MAX(0, insets.right)),
      @"bottom" : @(MAX(0, insets.bottom)),
      @"left" : @(MAX(0, insets.left)),
    },
  }];
  NSDictionary<NSString *, id> *overrides = additionalData[@"nativeEnvironment"];
  if ([overrides isKindOfClass:NSDictionary.class]) {
    [nativeEnvironment addEntriesFromDictionary:overrides];
  }
  data[@"nativeEnvironment"] = nativeEnvironment;
  return [[LynxTemplateData alloc] initWithDictionary:data];
}

// The @LynxNativeModule annotation is what cocoapods-lynx-library scans for;
// it expands to a harmless ObjC forward declaration when compiled.
// Device facts, safe area, status bar, display metrics, battery state and
// sensors exported to Lynx as `Device`. All widths are reported in Lynx
// logical pixels (points), the unit Lynx layout consumes. The gyroscope
// reports rad/s and the magnetometer microtesla, both straight from
// CoreMotion; the barometer converts CMAltitudeData pressure (kPa) into
// hectopascals so all three platforms report the same unit.
@LynxNativeModule("Device")
@implementation DeviceModule {
  __weak LynxContext *_lynxContext;
  CMMotionManager *_motionManager;
  CMAltimeter *_altimeter;
  CLLocationManager *_locationManager;
  BOOL _accelerometerActive;
  BOOL _compassActive;
  BOOL _gyroscopeActive;
  BOOL _magnetometerActive;
  BOOL _barometerActive;
  BOOL _destroyed;
}

- (instancetype)initWithLynxContext:(LynxContext *)context {
  self = [super init];
  if (self) {
    _lynxContext = context;
  }
  return self;
}

+ (NSString *)name {
  return @"Device";
}

+ (NSDictionary<NSString *, NSString *> *)methodLookup {
  return @{
    @"getInfo" : NSStringFromSelector(@selector(getInfo:)),
    @"getSafeAreaInsets" : NSStringFromSelector(@selector(getSafeAreaInsets:)),
    @"setStatusBarStyle" :
        NSStringFromSelector(@selector(setStatusBarStyle:callback:)),
    @"screenWidth" : NSStringFromSelector(@selector(screenWidth:)),
    @"windowWidth" : NSStringFromSelector(@selector(windowWidth:)),
    @"lynxViewWidth" : NSStringFromSelector(@selector(lynxViewWidth:)),
    @"getBrightness" : NSStringFromSelector(@selector(getBrightness:)),
    @"setBrightness" : NSStringFromSelector(@selector(setBrightness:callback:)),
    @"setKeepScreenOn" : NSStringFromSelector(@selector(setKeepScreenOn:callback:)),
    @"openAppSettings" : NSStringFromSelector(@selector(openAppSettings:)),
    @"getBatteryInfo" : NSStringFromSelector(@selector(getBatteryInfo:)),
    @"isAvailable" : NSStringFromSelector(@selector(isAvailable:callback:)),
    @"start" : NSStringFromSelector(@selector(start:callback:)),
    @"stop" : NSStringFromSelector(@selector(stop:callback:)),
  };
}

#pragma mark - Device facts, safe area and status bar

- (void)getInfo:(LynxCallbackBlock)callback {
  struct utsname systemInfo;
  uname(&systemInfo);
  // `machine` is the hardware identifier (e.g. "iPhone17,2"); UIDevice.model
  // only reports the generic family ("iPhone").
  NSString *model = @(systemInfo.machine);
  NSDictionary<NSString *, id> *bundleInfo = NSBundle.mainBundle.infoDictionary ?: @{};

  NSMutableDictionary<NSString *, id> *value = [NSMutableDictionary dictionary];
  value[@"model"] = model ?: @"";
  value[@"manufacturer"] = @"Apple";
  value[@"osVersion"] = UIDevice.currentDevice.systemVersion ?: @"";
  value[@"osApiLevel"] = NSNull.null;
  value[@"appVersion"] = bundleInfo[@"CFBundleShortVersionString"] ?: @"";
  value[@"appBuild"] = bundleInfo[@"CFBundleVersion"] ?: @"";
  value[@"bundleId"] = bundleInfo[@"CFBundleIdentifier"] ?: @"";
  value[@"density"] = @(UIScreen.mainScreen.scale);
  value[@"locale"] = NSLocale.currentLocale.localeIdentifier ?: @"";
  value[@"isTablet"] = [NSNumber
      numberWithBool:(UIDevice.currentDevice.userInterfaceIdiom ==
                      UIUserInterfaceIdiomPad)];
  value[@"isFoldable"] = @NO;

  callback(LynxDeviceJSON(@{ @"value" : value }));
}

- (void)getSafeAreaInsets:(LynxCallbackBlock)callback {
  dispatch_async(dispatch_get_main_queue(), ^{
    LynxView *lynxView = [self->_lynxContext getLynxView];
    if (lynxView == nil) {
      callback(LynxDeviceJSON(@{ @"error" : @"LynxView is not attached yet" }));
      return;
    }
    UIEdgeInsets insets = lynxView.safeAreaInsets;
    callback(LynxDeviceJSON(@{
      @"value" : @{
        @"top" : @(MAX(0, insets.top)),
        @"right" : @(MAX(0, insets.right)),
        @"bottom" : @(MAX(0, insets.bottom)),
        @"left" : @(MAX(0, insets.left)),
      },
    }));
  });
}

- (void)setStatusBarStyle:(NSString *)style
                 callback:(LynxCallbackBlock)callback {
  if (![style isEqualToString:LynxStatusBarStyleDarkContent] &&
      ![style isEqualToString:LynxStatusBarStyleLightContent]) {
    callback([NSString stringWithFormat:@"Invalid status bar style: %@", style]);
    return;
  }

  dispatch_async(dispatch_get_main_queue(), ^{
    UIResponder *responder = [self->_lynxContext getLynxView];
    while (responder != nil &&
           ![responder conformsToProtocol:@protocol(LynxDeviceStatusBarHost)]) {
      responder = responder.nextResponder;
    }
    id<LynxDeviceStatusBarHost> host =
        (id<LynxDeviceStatusBarHost>)responder;
    if (host == nil) {
      callback(@"Device has no status-bar page host");
      return;
    }
    [host setLynxStatusBarStyle:style];
    callback(@"");
  });
}

#pragma mark - Display metrics

- (void)screenWidth:(LynxCallbackBlock)callback {
  dispatch_async(dispatch_get_main_queue(), ^{
    callback([self valueString:UIScreen.mainScreen.bounds.size.width]);
  });
}

- (void)windowWidth:(LynxCallbackBlock)callback {
  dispatch_async(dispatch_get_main_queue(), ^{
    UIWindow *window = [self lynxView].window ?: [self keyWindow];
    if (window == nil) {
      // Without a window the app owns the full screen.
      callback([self valueString:UIScreen.mainScreen.bounds.size.width]);
      return;
    }
    callback([self valueString:window.bounds.size.width]);
  });
}

- (void)lynxViewWidth:(LynxCallbackBlock)callback {
  dispatch_async(dispatch_get_main_queue(), ^{
    LynxView *view = [self lynxView];
    if (view == nil) {
      callback(@"{\"error\":\"LynxView is not attached yet\"}");
      return;
    }
    // Zero means the view has not been laid out yet; it is reported as-is
    // so callers can distinguish it from an unavailable view.
    callback([self valueString:view.bounds.size.width]);
  });
}

// UIScreen.brightness is the system brightness as seen by this app; setting
// it needs no permission and is restored when the app leaves the foreground.
- (void)getBrightness:(LynxCallbackBlock)callback {
  dispatch_async(dispatch_get_main_queue(), ^{
    callback([self valueString:UIScreen.mainScreen.brightness]);
  });
}

- (void)setBrightness:(double)value callback:(LynxCallbackBlock)callback {
  dispatch_async(dispatch_get_main_queue(), ^{
    if (!isfinite(value) || value < 0 || value > 1) {
      callback(@"Brightness must be between 0 and 1");
      return;
    }
    UIScreen.mainScreen.brightness = (CGFloat)value;
    callback(@"");
  });
}

- (void)setKeepScreenOn:(BOOL)enabled callback:(LynxCallbackBlock)callback {
  dispatch_async(dispatch_get_main_queue(), ^{
    UIApplication.sharedApplication.idleTimerDisabled = !enabled;
    callback(@"");
  });
}

// openSettingsURLString is the only settings destination reachable through
// public APIs; the system opens this app's own settings page.
- (void)openAppSettings:(LynxCallbackBlock)callback {
  dispatch_async(dispatch_get_main_queue(), ^{
    NSURL *url = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
    if (url == nil) {
      callback(@"Device has no app settings URL");
      return;
    }
    [UIApplication.sharedApplication openURL:url
                                     options:@{}
                           completionHandler:^(BOOL success) {
      callback(success ? @"" : @"Unable to open app settings");
    }];
  });
}

#pragma mark - Battery

- (void)getBatteryInfo:(LynxCallbackBlock)callback {
  // Battery monitoring must be enabled before the values become readable;
  // simulators report `batteryLevel` -1 and state unknown, surfaced as null.
  UIDevice *device = UIDevice.currentDevice;
  device.batteryMonitoringEnabled = YES;

  float level = device.batteryLevel;
  BOOL charging = device.batteryState == UIDeviceBatteryStateCharging
      || device.batteryState == UIDeviceBatteryStateFull;

  NSDictionary<NSString *, id> *value = @{
    @"level" : level >= 0 ? @(level) : NSNull.null,
    @"charging" : @(charging),
  };

  callback(@{ @"value" : value });
}

#pragma mark - Motion sensors

- (void)destroy {
  @synchronized(self) {
    _destroyed = YES;
  }
  CMMotionManager *motion = _motionManager;
  CMAltimeter *altimeter = _altimeter;
  CLLocationManager *location = _locationManager;
  if (motion != nil) {
    dispatch_async(dispatch_get_main_queue(), ^{
      [motion stopAccelerometerUpdates];
      [motion stopGyroUpdates];
      [motion stopMagnetometerUpdates];
    });
  }
  if (altimeter != nil) {
    dispatch_async(dispatch_get_main_queue(), ^{
      [altimeter stopRelativeAltitudeUpdates];
    });
  }
  if (location != nil) {
    // CLLocationManager delivers delegate events on the run loop of the
    // thread it was created on; both are created on the main thread here.
    dispatch_async(dispatch_get_main_queue(), ^{
      [location stopUpdatingHeading];
    });
  }
  _accelerometerActive = NO;
  _compassActive = NO;
  _gyroscopeActive = NO;
  _magnetometerActive = NO;
  _barometerActive = NO;
}

- (void)isAvailable:(NSString *)type callback:(LynxCallbackBlock)callback {
  if ([type isEqualToString:kTypeAccelerometer]) {
    callback([self valueString:self.motionManager.isAccelerometerAvailable]);
    return;
  }
  if ([type isEqualToString:kTypeCompass]) {
    callback([self valueString:CLLocationManager.headingAvailable]);
    return;
  }
  if ([type isEqualToString:kTypeGyroscope]) {
    callback([self valueString:self.motionManager.isGyroAvailable]);
    return;
  }
  if ([type isEqualToString:kTypeMagnetometer]) {
    callback([self valueString:self.motionManager.isMagnetometerAvailable]);
    return;
  }
  if ([type isEqualToString:kTypeBarometer]) {
    callback([self valueString:CMAltimeter.isRelativeAltitudeAvailable]);
    return;
  }
  callback(@"Unknown sensor type");
}

- (void)start:(NSString *)type callback:(LynxCallbackBlock)callback {
  if (_destroyed) {
    callback(@"Device host has been destroyed");
    return;
  }
  if ([type isEqualToString:kTypeAccelerometer]) {
    [self startAccelerometer:callback];
    return;
  }
  if ([type isEqualToString:kTypeCompass]) {
    [self startCompass:callback];
    return;
  }
  if ([type isEqualToString:kTypeGyroscope]) {
    [self startGyroscope:callback];
    return;
  }
  if ([type isEqualToString:kTypeMagnetometer]) {
    [self startMagnetometer:callback];
    return;
  }
  if ([type isEqualToString:kTypeBarometer]) {
    [self startBarometer:callback];
    return;
  }
  callback(@"Unknown sensor type");
}

- (void)stop:(NSString *)type callback:(LynxCallbackBlock)callback {
  if ([type isEqualToString:kTypeAccelerometer]) {
    if (_accelerometerActive) {
      _accelerometerActive = NO;
      [self.motionManager stopAccelerometerUpdates];
    }
    callback(@"");
    return;
  }
  if ([type isEqualToString:kTypeCompass]) {
    if (_compassActive) {
      _compassActive = NO;
      [self stopHeadingUpdates];
    }
    callback(@"");
    return;
  }
  if ([type isEqualToString:kTypeGyroscope]) {
    if (_gyroscopeActive) {
      _gyroscopeActive = NO;
      [self.motionManager stopGyroUpdates];
    }
    callback(@"");
    return;
  }
  if ([type isEqualToString:kTypeMagnetometer]) {
    if (_magnetometerActive) {
      _magnetometerActive = NO;
      [self.motionManager stopMagnetometerUpdates];
    }
    callback(@"");
    return;
  }
  if ([type isEqualToString:kTypeBarometer]) {
    if (_barometerActive) {
      _barometerActive = NO;
      [self stopBarometerUpdates];
    }
    callback(@"");
    return;
  }
  callback(@"Unknown sensor type");
}

- (void)startAccelerometer:(LynxCallbackBlock)callback {
  if (_accelerometerActive) {
    callback(@"");
    return;
  }
  CMMotionManager *motion = self.motionManager;
  if (!motion.isAccelerometerAvailable) {
    callback(@"Accelerometer is unavailable");
    return;
  }
  __weak DeviceModule *weakSelf = self;
  _accelerometerActive = YES;
  dispatch_async(dispatch_get_main_queue(), ^{
    [weakSelf.motionManager
        startAccelerometerUpdatesToQueue:[NSOperationQueue mainQueue]
                             withHandler:^(CMAccelerometerData *data, NSError *error) {
                               DeviceModule *strongSelf = weakSelf;
                               if (strongSelf == nil || error != nil) {
                                 return;
                               }
                               [strongSelf emitTriple:kTypeAccelerometer
                                                     x:data.acceleration.x *
                                                       kStandardGravityMetersPerSecondSquared
                                                     y:data.acceleration.y *
                                                       kStandardGravityMetersPerSecondSquared
                                                     z:data.acceleration.z *
                                                       kStandardGravityMetersPerSecondSquared];
                             }];
  });
  callback(@"");
}

- (void)startGyroscope:(LynxCallbackBlock)callback {
  if (_gyroscopeActive) {
    callback(@"");
    return;
  }
  CMMotionManager *motion = self.motionManager;
  if (!motion.isGyroAvailable) {
    callback(@"Gyroscope is unavailable");
    return;
  }
  __weak DeviceModule *weakSelf = self;
  _gyroscopeActive = YES;
  dispatch_async(dispatch_get_main_queue(), ^{
    [weakSelf.motionManager
        startGyroUpdatesToQueue:[NSOperationQueue mainQueue]
                    withHandler:^(CMGyroData *data, NSError *error) {
                      DeviceModule *strongSelf = weakSelf;
                      if (strongSelf == nil || error != nil) {
                        return;
                      }
                      [strongSelf emitTriple:kTypeGyroscope
                                            x:data.rotationRate.x
                                            y:data.rotationRate.y
                                            z:data.rotationRate.z];
                    }];
  });
  callback(@"");
}

- (void)startMagnetometer:(LynxCallbackBlock)callback {
  if (_magnetometerActive) {
    callback(@"");
    return;
  }
  CMMotionManager *motion = self.motionManager;
  if (!motion.isMagnetometerAvailable) {
    callback(@"Magnetometer is unavailable");
    return;
  }
  __weak DeviceModule *weakSelf = self;
  _magnetometerActive = YES;
  dispatch_async(dispatch_get_main_queue(), ^{
    [weakSelf.motionManager
        startMagnetometerUpdatesToQueue:[NSOperationQueue mainQueue]
                            withHandler:^(CMMagnetometerData *data, NSError *error) {
                              DeviceModule *strongSelf = weakSelf;
                              if (strongSelf == nil || error != nil) {
                                return;
                              }
                              [strongSelf emitTriple:kTypeMagnetometer
                                                    x:data.magneticField.x
                                                    y:data.magneticField.y
                                                    z:data.magneticField.z];
                            }];
  });
  callback(@"");
}

// CMAltitudeData reports the pressure in kilopascals; the JS contract
// standardizes on hectopascals (millibars) to match Android.
- (void)startBarometer:(LynxCallbackBlock)callback {
  if (_barometerActive) {
    callback(@"");
    return;
  }
  if (!CMAltimeter.isRelativeAltitudeAvailable) {
    callback(@"Barometer is unavailable");
    return;
  }
  __weak DeviceModule *weakSelf = self;
  _barometerActive = YES;
  dispatch_async(dispatch_get_main_queue(), ^{
    [weakSelf.altimeterOnMain
        startRelativeAltitudeUpdatesToQueue:[NSOperationQueue mainQueue]
                                withHandler:^(CMAltitudeData *data, NSError *error) {
                                  DeviceModule *strongSelf = weakSelf;
                                  if (strongSelf == nil || error != nil) {
                                    return;
                                  }
                                  NSMutableDictionary *payload = [NSMutableDictionary dictionary];
                                  payload[@"type"] = kTypeBarometer;
                                  payload[@"pressure"] = @(data.pressure.doubleValue * 10.0);
                                  payload[@"timestamp"] =
                                      @((long long)(NSDate.date.timeIntervalSince1970 * 1000));
                                  [strongSelf emitEvent:payload];
                                }];
  });
  callback(@"");
}

- (void)stopBarometerUpdates {
  CMAltimeter *altimeter = _altimeter;
  if (altimeter == nil) {
    return;
  }
  dispatch_async(dispatch_get_main_queue(), ^{
    [altimeter stopRelativeAltitudeUpdates];
  });
}

- (void)startCompass:(LynxCallbackBlock)callback {
  if (_compassActive) {
    callback(@"");
    return;
  }
  if (!CLLocationManager.headingAvailable) {
    callback(@"Compass is unavailable");
    return;
  }
  // Heading requires location authorization; request it once if the status
  // is still undetermined and let the authorization delegate start (or fail)
  // the stream.
  _compassActive = YES;
  CLAuthorizationStatus status = [self currentAuthorizationStatus];
  if (status == kCLAuthorizationStatusNotDetermined) {
    __weak DeviceModule *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
      [weakSelf.locationManagerOnMain requestWhenInUseAuthorization];
    });
    callback(@"");
    return;
  }
  [self startHeadingUpdatesIfAuthorized];
  callback(@"");
}

- (void)startHeadingUpdatesIfAuthorized {
  CLAuthorizationStatus status = [self currentAuthorizationStatus];
  if (status != kCLAuthorizationStatusAuthorizedWhenInUse
      && status != kCLAuthorizationStatusAuthorizedAlways) {
    [self failCompass:@"Location permission was denied"];
    return;
  }
  __weak DeviceModule *weakSelf = self;
  dispatch_async(dispatch_get_main_queue(), ^{
    DeviceModule *strongSelf = weakSelf;
    if (strongSelf == nil) {
      return;
    }
    CLLocationManager *manager = strongSelf.locationManagerOnMain;
    manager.headingFilter = kCLHeadingFilterNone;
    [manager startUpdatingHeading];
  });
}

- (void)stopHeadingUpdates {
  CLLocationManager *location = _locationManager;
  if (location == nil) {
    return;
  }
  dispatch_async(dispatch_get_main_queue(), ^{
    [location stopUpdatingHeading];
  });
}

- (void)failCompass:(NSString *)message {
  _compassActive = NO;
  NSMutableDictionary *payload = [NSMutableDictionary dictionary];
  payload[@"type"] = kTypeCompass;
  payload[@"error"] = message;
  [self emitEvent:payload];
}

#pragma mark - CLLocationManagerDelegate

- (void)locationManagerDidChangeAuthorization:(CLLocationManager *)manager {
  if (!_compassActive) {
    return;
  }
  [self handleAuthorizationStatus:[self currentAuthorizationStatus]];
}

// Fires instead of locationManagerDidChangeAuthorization: before iOS 14.
- (void)locationManager:(CLLocationManager *)manager
    didChangeAuthorizationStatus:(CLAuthorizationStatus)status {
  if (!_compassActive) {
    return;
  }
  [self handleAuthorizationStatus:status];
}

- (void)handleAuthorizationStatus:(CLAuthorizationStatus)status {
  if (status == kCLAuthorizationStatusAuthorizedWhenInUse
      || status == kCLAuthorizationStatusAuthorizedAlways) {
    [self startHeadingUpdatesIfAuthorized];
    return;
  }
  if (status == kCLAuthorizationStatusDenied || status == kCLAuthorizationStatusRestricted) {
    [self failCompass:@"Location permission was denied"];
  }
}

- (void)locationManager:(CLLocationManager *)manager
       didUpdateHeading:(CLHeading *)newHeading {
  if (!_compassActive) {
    return;
  }
  double accuracy = newHeading.headingAccuracy;
  [self emitEvent:@{
    @"type" : kTypeCompass,
    @"heading" : @(newHeading.magneticHeading),
    @"accuracy" : @(accuracy < 0 ? -1.0 : accuracy),
    @"timestamp" : @((long long)(NSDate.date.timeIntervalSince1970 * 1000)),
  }];
}

- (BOOL)locationManagerShouldDisplayHeadingCalibration:(CLLocationManager *)manager {
  return NO;
}

#pragma mark - Helpers

// The class method is deprecated from iOS 14 but works on every version the
// app supports (deployment target 13.0); the instance property is 14+ only.
- (CLAuthorizationStatus)currentAuthorizationStatus {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
  return [CLLocationManager authorizationStatus];
#pragma clang diagnostic pop
}

- (CMMotionManager *)motionManager {
  if (_motionManager == nil) {
    _motionManager = [[CMMotionManager alloc] init];
  }
  return _motionManager;
}

- (CMAltimeter *)altimeterOnMain {
  NSAssert(NSThread.isMainThread, @"CMAltimeter must be created on the main thread");
  if (_altimeter == nil) {
    _altimeter = [[CMAltimeter alloc] init];
  }
  return _altimeter;
}

- (void)emitTriple:(NSString *)type
                 x:(double)x
                 y:(double)y
                 z:(double)z {
  [self emitEvent:@{
    @"type" : type,
    @"x" : @(x),
    @"y" : @(y),
    @"z" : @(z),
    @"timestamp" : @((long long)(NSDate.date.timeIntervalSince1970 * 1000)),
  }];
}

- (CLLocationManager *)locationManagerOnMain {
  NSAssert(NSThread.isMainThread, @"CLLocationManager must be created on the main thread");
  if (_locationManager == nil) {
    _locationManager = [[CLLocationManager alloc] init];
    _locationManager.delegate = self;
  }
  return _locationManager;
}

- (void)emitEvent:(NSDictionary *)payload {
  @synchronized(self) {
    if (_destroyed) {
      return;
    }
  }
  LynxContext *context = _lynxContext;
  dispatch_async(dispatch_get_main_queue(), ^{
    [context sendGlobalEvent:kEventName withParams:@[payload]];
  });
}

- (nullable LynxView *)lynxView {
  return [_lynxContext getLynxView];
}

- (nullable UIWindow *)keyWindow {
  for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
    if (![scene isKindOfClass:UIWindowScene.class] ||
        scene.activationState != UISceneActivationStateForegroundActive) {
      continue;
    }
    for (UIWindow *window in ((UIWindowScene *)scene).windows) {
      if (window.isKeyWindow) {
        return window;
      }
    }
  }
  return nil;
}

- (NSString *)valueString:(double)value {
  return [NSString stringWithFormat:@"{\"value\":%f}", value];
}

@end
