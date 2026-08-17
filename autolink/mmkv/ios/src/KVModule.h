#import <Foundation/Foundation.h>
#import <Lynx/LynxModule.h>

NS_ASSUME_NONNULL_BEGIN

/// Autolinked Lynx bridge exported as `KV`. JSON encoding
/// stays on the TypeScript side.
@interface KVModule : NSObject <LynxModule>

@end

NS_ASSUME_NONNULL_END
