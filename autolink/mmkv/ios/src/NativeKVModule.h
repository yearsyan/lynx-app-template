#import <Foundation/Foundation.h>
#import <Lynx/LynxModule.h>

NS_ASSUME_NONNULL_BEGIN

/// Autolinked Lynx module exposing MMKV-backed string storage. JSON encoding
/// stays on the TypeScript side.
@interface NativeKVModule : NSObject <LynxModule>

@end

NS_ASSUME_NONNULL_END
