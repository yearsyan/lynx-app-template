#import <Foundation/Foundation.h>
#import <Lynx/LynxModule.h>

NS_ASSUME_NONNULL_BEGIN

/// Autolinked Lynx bridge exported as `SecureStorage`. Values live in the
/// iOS Keychain as generic-password items bound to this device only.
@interface SecureStorageModule : NSObject <LynxModule>

@end

NS_ASSUME_NONNULL_END
