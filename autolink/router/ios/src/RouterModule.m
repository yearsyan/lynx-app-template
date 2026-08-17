#import "RouterModule.h"

#import <Lynx/LynxContext.h>
#import <UIKit/UIKit.h>

// The @LynxNativeModule annotation is what cocoapods-lynx-library scans for;
// it expands to a harmless ObjC forward declaration when compiled.
// Exported to Lynx as `Router`.
@LynxNativeModule("Router")
@implementation RouterModule {
  LynxContext *_context;
}

static id<LynxRouteHandler> _Nullable _routeHandler = nil;

+ (NSString *)name {
  return @"Router";
}

+ (NSDictionary<NSString *, NSString *> *)methodLookup {
  return @{
    @"open" : NSStringFromSelector(@selector(open:callback:)),
    @"close" : NSStringFromSelector(@selector(close:)),
    @"openURL" : NSStringFromSelector(@selector(openURL:callback:)),
  };
}

+ (void)setRouteHandler:(nullable id<LynxRouteHandler>)handler {
  _routeHandler = handler;
}

- (instancetype)initWithLynxContext:(LynxContext *)context {
  self = [super init];
  if (self) {
    _context = context;
  }
  return self;
}

- (void)open:(NSDictionary *)options callback:(LynxCallbackBlock)callback {
  id<LynxRouteHandler> handler = _routeHandler;
  UIViewController *host = [self presentingViewController];
  if (handler == nil || host == nil) {
    callback(@"Router has no visible UIViewController host");
    return;
  }
  [handler openFromViewController:host options:options success:callback];
}

- (void)close:(LynxCallbackBlock)callback {
  id<LynxRouteHandler> handler = _routeHandler;
  UIViewController *host = [self presentingViewController];
  if (handler == nil || host == nil) {
    callback(@"Router has no visible UIViewController host");
    return;
  }
  [handler closeFromViewController:host success:callback];
}

- (void)openURL:(NSString *)url callback:(LynxCallbackBlock)callback {
  dispatch_async(dispatch_get_main_queue(), ^{
    NSURL *target = [NSURL URLWithString:url];
    if (url == nil || url.length == 0 || target == nil || target.scheme.length == 0) {
      callback(@"Invalid URL");
      return;
    }
    [UIApplication.sharedApplication openURL:target
                                     options:@{}
                           completionHandler:^(BOOL success) {
      callback(success ? @"" : @"Unable to open URL");
    }];
  });
}

- (nullable UIViewController *)presentingViewController {
  UIViewController *root = _context.getLynxView.window.rootViewController;
  if (root == nil) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
      if (![scene isKindOfClass:UIWindowScene.class]) {
        continue;
      }
      for (UIWindow *window in ((UIWindowScene *)scene).windows) {
        if (window.isKeyWindow) {
          root = window.rootViewController;
          break;
        }
      }
      if (root != nil) {
        break;
      }
    }
  }
  return [self topViewController:root];
}

- (nullable UIViewController *)topViewController:(nullable UIViewController *)controller {
  if (controller.presentedViewController != nil) {
    return [self topViewController:controller.presentedViewController];
  }
  if ([controller isKindOfClass:UINavigationController.class]) {
    return [self topViewController:((UINavigationController *)controller).visibleViewController];
  }
  if ([controller isKindOfClass:UITabBarController.class]) {
    return [self topViewController:((UITabBarController *)controller).selectedViewController];
  }
  return controller;
}

@end
