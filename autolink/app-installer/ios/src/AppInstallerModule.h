#import <Foundation/Foundation.h>
#import <Lynx/LynxContextModule.h>

NS_ASSUME_NONNULL_BEGIN

/// Autolinked Lynx bridge exported to JavaScript as `AppInstaller`.
/// Declares LynxContextModule so the runtime instantiates it through
/// initWithLynxContext:, the designated initializer in the .m stub.
@interface AppInstallerModule : NSObject <LynxContextModule>

@end

NS_ASSUME_NONNULL_END
