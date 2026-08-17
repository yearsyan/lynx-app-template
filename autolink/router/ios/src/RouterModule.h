#import <Foundation/Foundation.h>
#import <Lynx/LynxModule.h>

NS_ASSUME_NONNULL_BEGIN

@class UIViewController;

/// Host-installed navigation for in-app Lynx bundle routes.
///
/// The autolinked Router module resolves the view controller hosting the
/// calling Lynx view and forwards `open`/`close` here, because only the
/// host knows how to present its Lynx pages. Implementations must be
/// stateless: the host argument identifies the calling route.
@protocol LynxRouteHandler <NSObject>

- (void)openFromViewController:(UIViewController *)host
                       options:(NSDictionary<NSString *, id> *)options
                       success:(LynxCallbackBlock)completion;

- (void)closeFromViewController:(UIViewController *)host
                        success:(LynxCallbackBlock)completion;

@end

/// Autolinked Lynx bridge exported to JavaScript as `Router`.
@interface RouterModule : NSObject <LynxModule>

/// Installs the host navigation delegate used by `open`/`close`.
+ (void)setRouteHandler:(nullable id<LynxRouteHandler>)handler;

@end

NS_ASSUME_NONNULL_END
