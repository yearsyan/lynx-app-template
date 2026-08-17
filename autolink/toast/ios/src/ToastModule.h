#import <Foundation/Foundation.h>
#import <Lynx/LynxContextModule.h>

NS_ASSUME_NONNULL_BEGIN

/// Autolinked Lynx bridge exported to JavaScript as `Toast`.
/// Conforms to LynxContextModule so the toast prefers the LynxView's window.
@interface ToastModule : NSObject <LynxContextModule>

@end

NS_ASSUME_NONNULL_END
