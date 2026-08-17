#import "DeviceInfoModule.h"

#import <UIKit/UIKit.h>
#import <sys/utsname.h>

// The @LynxNativeModule annotation is what cocoapods-lynx-library scans for;
// it expands to a harmless ObjC forward declaration when compiled.
// Exported to Lynx as `DeviceInfo`.
@LynxNativeModule("DeviceInfo")
@implementation DeviceInfoModule

+ (NSString *)name {
  return @"DeviceInfo";
}

+ (NSDictionary<NSString *, NSString *> *)methodLookup {
  return @{
    @"getInfo" : NSStringFromSelector(@selector(getInfo:)),
  };
}

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
  value[@"density"] = @(UIScreen.mainScreen.scale);
  value[@"locale"] = NSLocale.currentLocale.localeIdentifier ?: @"";
  value[@"isTablet"] =
      @(UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad);
  value[@"isFoldable"] = @NO;

  NSData *data = [NSJSONSerialization dataWithJSONObject:@{ @"value" : value }
                                                 options:0
                                                   error:nil];
  callback(data ? [[NSString alloc] initWithData:data
                                        encoding:NSUTF8StringEncoding]
                : @"{\"error\":\"DeviceInfo serialization failed\"}");
}

@end
