#import "AppInstallerModule.h"

// The @LynxNativeModule annotation is what cocoapods-lynx-library scans for;
// it expands to a harmless ObjC forward declaration when compiled.
// iOS has no public arbitrary-package installer hand-off, so this opt-in
// module exposes capability discovery and explicit unsupported errors.
@LynxNativeModule("AppInstaller")
@implementation AppInstallerModule

+ (NSString *)name {
  return @"AppInstaller";
}

+ (NSDictionary<NSString *, NSString *> *)methodLookup {
  return @{
    @"getCapabilities" : NSStringFromSelector(@selector(getCapabilities:)),
    @"openPermissionSettings" :
        NSStringFromSelector(@selector(openPermissionSettings:)),
    @"launchInstall" :
        NSStringFromSelector(@selector(launchInstall:callback:)),
  };
}

- (instancetype)initWithLynxContext:(LynxContext *)context {
  return [super init];
}

- (void)getCapabilities:(LynxCallbackBlock)callback {
  callback(@{
    @"value" : @{ @"supported" : @NO, @"permissionGranted" : @NO },
    @"error" : @"",
  });
}

- (void)openPermissionSettings:(LynxCallbackBlock)callback {
  callback(@"AppInstaller is not supported on iOS");
}

- (void)launchInstall:(NSDictionary *)options
              callback:(LynxCallbackBlock)callback {
  callback(@{
    @"value" : NSNull.null,
    @"error" : @"AppInstaller is not supported on iOS",
  });
}

@end
