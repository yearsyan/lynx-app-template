#import <Foundation/Foundation.h>
#import <Lynx/LynxContextModule.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class UIViewController;

/// Host-installed navigation for in-app Lynx bundle routes.
///
/// The autolinked Navigation module resolves the view controller hosting the
/// calling Lynx view and forwards `open`/`close` here, because only the host
/// knows how to present its Lynx pages. Implementations must be stateless:
/// the host argument identifies the calling route. The result-routing methods
/// are exempt: they correlate the opened route with the opener's pending
/// result callback through a host-owned registry.
@protocol LynxRouteHandler <NSObject>

- (void)openFromViewController:(UIViewController *)host
                       options:(NSDictionary<NSString *, id> *)options
                       success:(LynxCallbackBlock)completion;

- (void)closeFromViewController:(UIViewController *)host
                        success:(LynxCallbackBlock)completion;

@optional

/// Opens another Lynx bundle and keeps `resultCallback` pending until the
/// opened route closes. The callback is invoked exactly once with a JSON
/// envelope: `{"error": message}` when the open fails, otherwise
/// `{"value": result}` after a `closeWithResult`, or `{}` when the route
/// closed without one.
- (void)openForResultFromViewController:(UIViewController *)host
                                options:(NSDictionary<NSString *, id> *)options
                              onResult:(LynxCallbackBlock)resultCallback;

/// Closes the route hosted by `host`, delivering `result` to the opener's
/// pending openForResult callback when the route was opened for a result;
/// the result is dropped otherwise.
- (void)closeWithResultFromViewController:(UIViewController *)host
                                   result:(NSDictionary<NSString *, id> *)result
                                  success:(LynxCallbackBlock)completion;

@end

/// Autolinked route navigation and Back interception bridge. It discovers the
/// UIViewController that owns the current LynxView and therefore needs no
/// page-specific module parameter.
@interface LynxNavigationModule : NSObject <LynxContextModule, UIGestureRecognizerDelegate>

/// Installs the host navigation delegate used by `open`/`close`.
+ (void)setRouteHandler:(nullable id<LynxRouteHandler>)handler;

@end

NS_ASSUME_NONNULL_END
