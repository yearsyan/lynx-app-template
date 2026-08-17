#import <Foundation/Foundation.h>
#import <Lynx/LynxContextModule.h>

NS_ASSUME_NONNULL_BEGIN

/// Autolinked Lynx bridge exported as `WebSocket`; the transport is
/// independent of Lynx DevTool. Events flow back to JS through the injected
/// LynxContext instead of a host-owned controller.
@interface WebSocketModule : NSObject <LynxContextModule>

@end

NS_ASSUME_NONNULL_END
