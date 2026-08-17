#import "NativeClipboardModule.h"

#import <UIKit/UIPasteboard.h>

// The @LynxNativeModule annotation is what cocoapods-lynx-library scans for;
// it expands to a harmless ObjC forward declaration when compiled.
@LynxNativeModule("NativeClipboardModule")
@implementation NativeClipboardModule

+ (NSString *)name {
  return @"NativeClipboardModule";
}

+ (NSDictionary<NSString *, NSString *> *)methodLookup {
  return @{
    @"setString" : NSStringFromSelector(@selector(setString:callback:)),
    @"getString" : NSStringFromSelector(@selector(getString:)),
  };
}

- (void)setString:(NSString *)text callback:(LynxCallbackBlock)callback {
  dispatch_async(dispatch_get_main_queue(), ^{
    UIPasteboard.generalPasteboard.string = text;
    callback(@"");
  });
}

- (void)getString:(LynxCallbackBlock)callback {
  dispatch_async(dispatch_get_main_queue(), ^{
    callback(UIPasteboard.generalPasteboard.string ?: NSNull.null);
  });
}

@end
