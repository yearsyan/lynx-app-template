#import <Foundation/Foundation.h>
#import <Lynx/LynxContextModule.h>

NS_ASSUME_NONNULL_BEGIN

/// Autolinked Lynx bridge exported to JavaScript as `Screenshot`.
/// Conforms to LynxContextModule so it can reach the owning LynxView.
@interface ScreenshotModule : NSObject <LynxContextModule>

@end

NS_ASSUME_NONNULL_END
