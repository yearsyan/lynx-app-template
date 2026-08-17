#import "BatteryModule.h"

#import <UIKit/UIKit.h>

// The @LynxNativeModule annotation is what cocoapods-lynx-library scans for;
// it expands to a harmless ObjC forward declaration when compiled.
// Exported to Lynx as `Battery`.
@LynxNativeModule("Battery")
@implementation BatteryModule

+ (NSString *)name {
  return @"Battery";
}

+ (NSDictionary<NSString *, NSString *> *)methodLookup {
  return @{
    @"getInfo" : NSStringFromSelector(@selector(getInfo:)),
  };
}

- (void)getInfo:(LynxCallbackBlock)callback {
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

  NSData *data = [NSJSONSerialization dataWithJSONObject:@{ @"value" : value }
                                                 options:0
                                                   error:nil];
  callback(data ? [[NSString alloc] initWithData:data
                                        encoding:NSUTF8StringEncoding]
                : @"{\"error\":\"Battery serialization failed\"}");
}

@end
