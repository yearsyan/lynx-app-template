#import "DeviceInfoModule.h"

#import <Lynx/LynxContext.h>
#import <Lynx/LynxView.h>
#import <sys/utsname.h>

static NSString *const LynxStatusBarStyleDarkContent = @"dark-content";
static NSString *const LynxStatusBarStyleLightContent = @"light-content";

static NSString *LynxDeviceInfoJSON(NSDictionary<NSString *, id> *result) {
  NSError *error = nil;
  NSData *data = [NSJSONSerialization dataWithJSONObject:result
                                                 options:0
                                                   error:&error];
  if (data == nil) {
    NSString *message = error.localizedDescription ?: @"serialization failed";
    NSDictionary<NSString *, id> *fallback = @{
      @"error" : [@"DeviceInfo " stringByAppendingString:message],
    };
    data = [NSJSONSerialization dataWithJSONObject:fallback options:0 error:nil];
  }
  return data == nil
             ? @"{\"error\":\"DeviceInfo serialization failed\"}"
             : [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

LynxTemplateData *LynxDeviceInfoTemplateData(
    UIEdgeInsets insets,
    NSDictionary<NSString *, id> *_Nullable additionalData) {
  NSMutableDictionary<NSString *, id> *data =
      [NSMutableDictionary dictionaryWithDictionary:additionalData ?: @{}];
  data[@"nativeEnvironment"] = @{
    @"schemaVersion" : @1,
    @"unit" : @"px",
    @"safeAreaInsets" : @{
      @"top" : @(MAX(0, insets.top)),
      @"right" : @(MAX(0, insets.right)),
      @"bottom" : @(MAX(0, insets.bottom)),
      @"left" : @(MAX(0, insets.left)),
    },
  };
  return [[LynxTemplateData alloc] initWithDictionary:data];
}

// The @LynxNativeModule annotation is what cocoapods-lynx-library scans for;
// it expands to a harmless ObjC forward declaration when compiled.
// Exported to Lynx as `DeviceInfo`.
@LynxNativeModule("DeviceInfo")
@implementation DeviceInfoModule {
  __weak LynxContext *_lynxContext;
}

- (instancetype)initWithLynxContext:(LynxContext *)context {
  self = [super init];
  if (self) {
    _lynxContext = context;
  }
  return self;
}

+ (NSString *)name {
  return @"DeviceInfo";
}

+ (NSDictionary<NSString *, NSString *> *)methodLookup {
  return @{
    @"getInfo" : NSStringFromSelector(@selector(getInfo:)),
    @"getSafeAreaInsets" : NSStringFromSelector(@selector(getSafeAreaInsets:)),
    @"setStatusBarStyle" :
        NSStringFromSelector(@selector(setStatusBarStyle:callback:)),
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

  callback(LynxDeviceInfoJSON(@{ @"value" : value }));
}

- (void)getSafeAreaInsets:(LynxCallbackBlock)callback {
  dispatch_async(dispatch_get_main_queue(), ^{
    LynxView *lynxView = [self->_lynxContext getLynxView];
    if (lynxView == nil) {
      callback(LynxDeviceInfoJSON(@{ @"error" : @"LynxView is not attached yet" }));
      return;
    }
    UIEdgeInsets insets = lynxView.safeAreaInsets;
    callback(LynxDeviceInfoJSON(@{
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
           ![responder conformsToProtocol:@protocol(LynxDeviceInfoStatusBarHost)]) {
      responder = responder.nextResponder;
    }
    id<LynxDeviceInfoStatusBarHost> host =
        (id<LynxDeviceInfoStatusBarHost>)responder;
    if (host == nil) {
      callback(@"DeviceInfo has no status-bar page host");
      return;
    }
    [host setLynxStatusBarStyle:style];
    callback(@"");
  });
}

@end
