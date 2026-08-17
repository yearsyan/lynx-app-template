#import "HapticsModule.h"

#import <UIKit/UIImpactFeedbackGenerator.h>

// The @LynxNativeModule annotation is what cocoapods-lynx-library scans for;
// it expands to a harmless ObjC forward declaration when compiled.
// Exported to Lynx as `Haptics`.
@LynxNativeModule("Haptics")
@implementation HapticsModule

+ (NSString *)name {
  return @"Haptics";
}

+ (NSDictionary<NSString *, NSString *> *)methodLookup {
  return @{
    @"impact" : NSStringFromSelector(@selector(impact:callback:)),
  };
}

- (void)impact:(NSString *)style callback:(LynxCallbackBlock)callback {
  UIImpactFeedbackStyle feedbackStyle;
  if ([style isEqualToString:@"light"]) {
    feedbackStyle = UIImpactFeedbackStyleLight;
  } else if ([style isEqualToString:@"medium"]) {
    feedbackStyle = UIImpactFeedbackStyleMedium;
  } else if ([style isEqualToString:@"heavy"]) {
    feedbackStyle = UIImpactFeedbackStyleHeavy;
  } else {
    callback([NSString stringWithFormat:@"Invalid haptic impact style: %@",
                                      style ?: @""]);
    return;
  }
  dispatch_async(dispatch_get_main_queue(), ^{
    UIImpactFeedbackGenerator *generator =
        [[UIImpactFeedbackGenerator alloc] initWithStyle:feedbackStyle];
    [generator prepare];
    [generator impactOccurred];
    callback(@"");
  });
}

@end
