#import "ToastModule.h"

#import <Lynx/LynxContext.h>
#import <Lynx/LynxView.h>
#import <UIKit/UIKit.h>

// The @LynxNativeModule annotation is what cocoapods-lynx-library scans for;
// it expands to a harmless ObjC forward declaration when compiled.
// Exported to Lynx as `Toast`. iOS has no system toast, so the module
// renders its own transient bubble above the host window — which also keeps
// styling fully in the app's hands and needs no notification permission.
@LynxNativeModule("Toast")
@implementation ToastModule {
  __weak LynxContext *_lynxContext;
}

static const NSInteger kToastViewTag = 0x4C5954;  // 'LYT'
static const CGFloat kToastHorizontalPadding = 14;
static const CGFloat kToastVerticalPadding = 10;
static const CGFloat kToastMaxWidthFraction = 0.8;
static const CGFloat kToastBottomOffset = 72;
static const CGFloat kToastIconSize = 18;
static const CGFloat kToastIconGap = 8;

- (instancetype)initWithLynxContext:(LynxContext *)context {
  self = [super init];
  if (self) {
    _lynxContext = context;
  }
  return self;
}

+ (NSString *)name {
  return @"Toast";
}

+ (NSDictionary<NSString *, NSString *> *)methodLookup {
  return @{
    @"show" : NSStringFromSelector(@selector(show:options:callback:)),
  };
}

- (void)show:(NSString *)message
     options:(NSDictionary *)options
    callback:(LynxCallbackBlock)callback {
  NSString *type = [options[@"type"] isKindOfClass:NSString.class]
                       ? options[@"type"]
                       : @"info";
  BOOL showIcon = [options[@"showIcon"] respondsToSelector:@selector(boolValue)]
                      ? [options[@"showIcon"] boolValue]
                      : YES;
  UIColor *backgroundColor =
      [self colorFromHex:options[@"backgroundColor"]]
          ?: [UIColor colorWithRed:0x2E / 255.0
                             green:0x2A / 255.0
                              blue:0x33 / 255.0
                             alpha:0.9];
  UIColor *textColor =
      [self colorFromHex:options[@"textColor"]] ?: UIColor.whiteColor;
  NSTimeInterval duration =
      MAX(0.5, [options[@"durationMs"] respondsToSelector:@selector(doubleValue)]
                   ? [options[@"durationMs"] doubleValue] / 1000.0
                   : 2.0);

  dispatch_async(dispatch_get_main_queue(), ^{
    UIWindow *window = [self lynxView].window ?: [self keyWindow];
    if (window == nil) {
      callback(@"Toast has no window");
      return;
    }
    [[window viewWithTag:kToastViewTag] removeFromSuperview];
    UIView *toast = [self makeToastWithText:message
                                       type:type
                                   showIcon:showIcon
                            backgroundColor:backgroundColor
                                  textColor:textColor
                                   inWindow:window];
    [window addSubview:toast];
    [UIView animateWithDuration:0.2
                     animations:^{
                       toast.alpha = 1;
                     }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(duration * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
                     [UIView animateWithDuration:0.25
                         animations:^{
                           toast.alpha = 0;
                         }
                         completion:^(BOOL finished) {
                           [toast removeFromSuperview];
                         }];
                   });
    callback(@"");
  });
}

- (UIView *)makeToastWithText:(NSString *)text
                         type:(NSString *)type
                     showIcon:(BOOL)showIcon
              backgroundColor:(UIColor *)backgroundColor
                    textColor:(UIColor *)textColor
                     inWindow:(UIWindow *)window {
  UILabel *label = [[UILabel alloc] init];
  label.text = text;
  label.textColor = textColor;
  label.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
  label.numberOfLines = 3;
  label.textAlignment = NSTextAlignmentCenter;

  CGFloat iconSpace = showIcon ? kToastIconSize + kToastIconGap : 0;
  CGFloat maxTextWidth = window.bounds.size.width * kToastMaxWidthFraction -
                         kToastHorizontalPadding * 2 - iconSpace;
  CGSize textSize = [label sizeThatFits:CGSizeMake(maxTextWidth, CGFLOAT_MAX)];
  textSize = CGSizeMake(ceil(textSize.width), ceil(textSize.height));

  CGFloat width =
      textSize.width + kToastHorizontalPadding * 2 + iconSpace;
  CGFloat height =
      MAX(textSize.height, showIcon ? kToastIconSize : 0) +
      kToastVerticalPadding * 2;

  UIView *toast = [[UIView alloc] initWithFrame:CGRectZero];
  toast.tag = kToastViewTag;
  toast.alpha = 0;
  toast.userInteractionEnabled = NO;
  toast.backgroundColor = backgroundColor;
  toast.layer.cornerRadius = height / 2;
  toast.layer.masksToBounds = YES;

  CGFloat contentX = kToastHorizontalPadding;
  if (showIcon) {
    UILabel *icon = [[UILabel alloc]
        initWithFrame:CGRectMake(contentX, (height - kToastIconSize) / 2,
                                 kToastIconSize, kToastIconSize)];
    icon.text = [self glyphForType:type];
    icon.textColor = UIColor.whiteColor;
    icon.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
    icon.textAlignment = NSTextAlignmentCenter;
    icon.backgroundColor = [self iconColorForType:type];
    icon.layer.cornerRadius = kToastIconSize / 2;
    icon.layer.masksToBounds = YES;
    [toast addSubview:icon];
    contentX += kToastIconSize + kToastIconGap;
  }

  label.frame = CGRectMake(contentX, (height - textSize.height) / 2,
                           textSize.width, textSize.height);
  [toast addSubview:label];

  CGFloat originX = (window.bounds.size.width - width) / 2;
  CGFloat originY = window.bounds.size.height -
                    window.safeAreaInsets.bottom - kToastBottomOffset - height;
  toast.frame = CGRectMake(originX, MAX(originY, 0), width, height);
  return toast;
}

- (NSString *)glyphForType:(NSString *)type {
  if ([type isEqualToString:@"success"]) {
    return @"✓";
  }
  if ([type isEqualToString:@"error"]) {
    return @"✕";
  }
  return @"i";
}

- (UIColor *)iconColorForType:(NSString *)type {
  if ([type isEqualToString:@"success"]) {
    return [UIColor colorWithRed:0x4C / 255.0
                           green:0xAF / 255.0
                            blue:0x7D / 255.0
                           alpha:1];
  }
  if ([type isEqualToString:@"error"]) {
    return [UIColor colorWithRed:0xE4 / 255.0
                           green:0x55 / 255.0
                            blue:0x6D / 255.0
                           alpha:1];
  }
  return [UIColor colorWithRed:0x8E / 255.0
                         green:0x8A / 255.0
                          blue:0x96 / 255.0
                         alpha:1];
}

/// Parses `#RRGGBB` or `#AARRGGBB`; nil for anything else.
- (nullable UIColor *)colorFromHex:(nullable id)value {
  if (![value isKindOfClass:NSString.class]) {
    return nil;
  }
  NSString *hex = (NSString *)value;
  if (![hex hasPrefix:@"#"]) {
    return nil;
  }
  unsigned int rgba = 0;
  if (![[NSScanner scannerWithString:[hex substringFromIndex:1]]
          scanHexInt:&rgba]) {
    return nil;
  }
  NSUInteger length = hex.length - 1;
  if (length == 6) {
    return [UIColor colorWithRed:((rgba >> 16) & 0xFF) / 255.0
                           green:((rgba >> 8) & 0xFF) / 255.0
                            blue:(rgba & 0xFF) / 255.0
                           alpha:1];
  }
  if (length == 8) {
    return [UIColor colorWithRed:((rgba >> 16) & 0xFF) / 255.0
                           green:((rgba >> 8) & 0xFF) / 255.0
                            blue:(rgba & 0xFF) / 255.0
                           alpha:((rgba >> 24) & 0xFF) / 255.0];
  }
  return nil;
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

@end
