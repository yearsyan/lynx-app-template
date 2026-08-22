#import <Foundation/Foundation.h>
#import <Lynx/LynxContextModule.h>
#import <Lynx/LynxTemplateData.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// The page host only owns UIKit's preferred-status-bar-style invalidation.
/// DeviceModule performs validation and finds this adapter from LynxView's
/// responder chain, so no app-owned Lynx module is required.
@protocol LynxDeviceStatusBarHost <NSObject>

- (void)setLynxStatusBarStyle:(NSString *)style;

@end

/// Builds the first-frame/reactive nativeEnvironment payload consumed by the
/// TypeScript facade. Hosts may merge route or other page-scoped init data.
FOUNDATION_EXPORT LynxTemplateData *LynxDeviceTemplateData(
    UIEdgeInsets insets,
    NSDictionary<NSString *, id> *_Nullable additionalData);

/// Autolinked device, display, battery and sensors bridge exported to
/// JavaScript as `Device`.
@interface DeviceModule : NSObject <LynxContextModule>

@end

NS_ASSUME_NONNULL_END
