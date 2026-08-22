#import <Foundation/Foundation.h>
#import <Lynx/LynxModule.h>

NS_ASSUME_NONNULL_BEGIN

/// Autolinked storage bridge exported to JavaScript as `Storage`. Plain
/// string primitives live in the shared MMKV instance; secure values live
/// in the iOS Keychain as generic-password items bound to this device only.
@interface StorageModule : NSObject <LynxModule>

@end

NS_ASSUME_NONNULL_END
