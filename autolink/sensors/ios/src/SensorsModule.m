#import "SensorsModule.h"

#import <CoreLocation/CoreLocation.h>
#import <CoreMotion/CoreMotion.h>
#import <Lynx/LynxContext.h>

static NSString *const kEventName = @"sensors";
static NSString *const kTypeAccelerometer = @"accelerometer";
static NSString *const kTypeCompass = @"compass";

// The @LynxNativeModule annotation is what cocoapods-lynx-library scans for;
// it expands to a harmless ObjC forward declaration when compiled.
// Exported to Lynx as `Sensors`.
@LynxNativeModule("Sensors")
@implementation SensorsModule {
  LynxContext *_context;
  CMMotionManager *_motionManager;
  CLLocationManager *_locationManager;
  BOOL _accelerometerActive;
  BOOL _compassActive;
  BOOL _destroyed;
}

+ (NSString *)name {
  return @"Sensors";
}

+ (NSDictionary<NSString *, NSString *> *)methodLookup {
  return @{
    @"isAvailable" : NSStringFromSelector(@selector(isAvailable:callback:)),
    @"start" : NSStringFromSelector(@selector(start:callback:)),
    @"stop" : NSStringFromSelector(@selector(stop:callback:)),
  };
}

- (instancetype)initWithLynxContext:(LynxContext *)context {
  self = [super init];
  if (self) {
    _context = context;
  }
  return self;
}

- (void)destroy {
  @synchronized(self) {
    _destroyed = YES;
  }
  CMMotionManager *motion = _motionManager;
  CLLocationManager *location = _locationManager;
  if (motion != nil) {
    dispatch_async(dispatch_get_main_queue(), ^{
      [motion stopAccelerometerUpdates];
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
}

#pragma mark - Module methods

- (void)isAvailable:(NSString *)type callback:(LynxCallbackBlock)callback {
  if ([type isEqualToString:kTypeAccelerometer]) {
    callback([self valueString:self.motionManager.isAccelerometerAvailable]);
    return;
  }
  if ([type isEqualToString:kTypeCompass]) {
    callback([self valueString:CLLocationManager.headingAvailable]);
    return;
  }
  callback(@"Unknown sensor type");
}

- (void)start:(NSString *)type callback:(LynxCallbackBlock)callback {
  if (_destroyed) {
    callback(@"Sensors host has been destroyed");
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
  callback(@"Unknown sensor type");
}

#pragma mark - Accelerometer

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
  __weak SensorsModule *weakSelf = self;
  _accelerometerActive = YES;
  dispatch_async(dispatch_get_main_queue(), ^{
    [weakSelf.motionManager
        startAccelerometerUpdatesToQueue:[NSOperationQueue mainQueue]
                             withHandler:^(CMAccelerometerData *data, NSError *error) {
                               SensorsModule *strongSelf = weakSelf;
                               if (strongSelf == nil || error != nil) {
                                 return;
                               }
                               [strongSelf emitEvent:@{
                                 @"type" : kTypeAccelerometer,
                                 @"x" : @(data.acceleration.x),
                                 @"y" : @(data.acceleration.y),
                                 @"z" : @(data.acceleration.z),
                                 @"timestamp" : @((long long)(NSDate.date.timeIntervalSince1970 * 1000)),
                               }];
                             }];
  });
  callback(@"");
}

#pragma mark - Compass

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
    __weak SensorsModule *weakSelf = self;
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
  __weak SensorsModule *weakSelf = self;
  dispatch_async(dispatch_get_main_queue(), ^{
    SensorsModule *strongSelf = weakSelf;
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
  LynxContext *context = _context;
  dispatch_async(dispatch_get_main_queue(), ^{
    [context sendGlobalEvent:kEventName withParams:@[payload]];
  });
}

- (NSString *)valueString:(BOOL)value {
  return value ? @"{\"value\":true}" : @"{\"value\":false}";
}

@end
