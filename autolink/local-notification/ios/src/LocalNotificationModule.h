#import <Foundation/Foundation.h>
#import <Lynx/LynxContextModule.h>

NS_ASSUME_NONNULL_BEGIN

/// Autolinked Lynx bridge exported to JavaScript as `LocalNotification`.
/// Declares LynxContextModule so the runtime instantiates it through
/// initWithLynxContext:, the designated initializer in the .m stub.
@interface LocalNotificationModule : NSObject <LynxContextModule>

@end

NS_ASSUME_NONNULL_END
