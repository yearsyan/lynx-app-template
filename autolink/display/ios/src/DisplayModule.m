#import "DisplayModule.h"

#import <Lynx/LynxContext.h>
#import <Lynx/LynxView.h>
#import <UIKit/UIKit.h>

// The @LynxNativeModule annotation is what cocoapods-lynx-library scans for;
// it expands to a harmless ObjC forward declaration when compiled.
// Exported to Lynx as `Display`. All widths are reported in Lynx logical
// pixels (points), the unit Lynx layout consumes.
@LynxNativeModule("Display")
@implementation DisplayModule {
  __weak LynxContext *_lynxContext;
}

- (instancetype)initWithLynxContext:(LynxContext *)context {
  self = [super init];
  if (self) {
    _lynxContext = context;
  }
  return self;
}

+ (NSString *)name {
  return @"Display";
}

+ (NSDictionary<NSString *, NSString *> *)methodLookup {
  return @{
    @"screenWidth" : NSStringFromSelector(@selector(screenWidth:)),
    @"windowWidth" : NSStringFromSelector(@selector(windowWidth:)),
    @"lynxViewWidth" : NSStringFromSelector(@selector(lynxViewWidth:)),
    @"getBrightness" : NSStringFromSelector(@selector(getBrightness:)),
    @"setBrightness" : NSStringFromSelector(@selector(setBrightness:callback:)),
    @"setKeepScreenOn" : NSStringFromSelector(@selector(setKeepScreenOn:callback:)),
  };
}

- (void)screenWidth:(LynxCallbackBlock)callback {
  dispatch_async(dispatch_get_main_queue(), ^{
    callback([self valueString:UIScreen.mainScreen.bounds.size.width]);
  });
}

- (void)windowWidth:(LynxCallbackBlock)callback {
  dispatch_async(dispatch_get_main_queue(), ^{
    UIWindow *window = [self lynxView].window ?: [self keyWindow];
    if (window == nil) {
      // Without a window the app owns the full screen.
      callback([self valueString:UIScreen.mainScreen.bounds.size.width]);
      return;
    }
    callback([self valueString:window.bounds.size.width]);
  });
}

- (void)lynxViewWidth:(LynxCallbackBlock)callback {
  dispatch_async(dispatch_get_main_queue(), ^{
    LynxView *view = [self lynxView];
    if (view == nil) {
      callback(@"{\"error\":\"LynxView is not attached yet\"}");
      return;
    }
    // Zero means the view has not been laid out yet; it is reported as-is
    // so callers can distinguish it from an unavailable view.
    callback([self valueString:view.bounds.size.width]);
  });
}

// UIScreen.brightness is the system brightness as seen by this app; setting
// it needs no permission and is restored when the app leaves the foreground.
- (void)getBrightness:(LynxCallbackBlock)callback {
  dispatch_async(dispatch_get_main_queue(), ^{
    callback([self valueString:UIScreen.mainScreen.brightness]);
  });
}

- (void)setBrightness:(double)value callback:(LynxCallbackBlock)callback {
  dispatch_async(dispatch_get_main_queue(), ^{
    if (!isfinite(value) || value < 0 || value > 1) {
      callback(@"Brightness must be between 0 and 1");
      return;
    }
    UIScreen.mainScreen.brightness = (CGFloat)value;
    callback(@"");
  });
}

- (void)setKeepScreenOn:(BOOL)enabled callback:(LynxCallbackBlock)callback {
  dispatch_async(dispatch_get_main_queue(), ^{
    UIApplication.sharedApplication.idleTimerDisabled = !enabled;
    callback(@"");
  });
}

- (nullable LynxView *)lynxView {
  return [_lynxContext getLynxView];
}

- (nullable UIWindow *)keyWindow {
  for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
    if (![scene isKindOfClass:UIWindowScene.class] ||
        scene.activationState != UISceneActivationStateForegroundActive) {
      continue;
    }
    for (UIWindow *window in ((UIWindowScene *)scene).windows) {
      if (window.isKeyWindow) {
        return window;
      }
    }
  }
  return nil;
}

- (NSString *)valueString:(CGFloat)width {
  return [NSString stringWithFormat:@"{\"value\":%f}", (double)width];
}

@end
