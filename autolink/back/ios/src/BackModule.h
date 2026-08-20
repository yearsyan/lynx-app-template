#import <Foundation/Foundation.h>
#import <Lynx/LynxContextModule.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Autolinked Back bridge. It discovers the UIViewController that owns the
/// current LynxView and therefore needs no page-specific module parameter.
@interface BackModule : NSObject <LynxContextModule, UIGestureRecognizerDelegate>

@end

NS_ASSUME_NONNULL_END
