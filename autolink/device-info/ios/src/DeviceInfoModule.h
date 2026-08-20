#import <Foundation/Foundation.h>
#import <Lynx/LynxModule.h>
#import <Lynx/LynxTemplateData.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// The page host only owns UIKit's preferred-status-bar-style invalidation.
/// DeviceInfoModule performs validation and finds this adapter from LynxView's
/// responder chain, so no app-owned Lynx module is required.
@protocol LynxDeviceInfoStatusBarHost <NSObject>

- (void)setLynxStatusBarStyle:(NSString *)style;

@end

/// Builds the first-frame/reactive nativeEnvironment payload consumed by the
/// TypeScript facade. Hosts may merge route or other page-scoped init data.
FOUNDATION_EXPORT LynxTemplateData *LynxDeviceInfoTemplateData(
    UIEdgeInsets insets,
    NSDictionary<NSString *, id> *_Nullable additionalData);

/// Autolinked Lynx bridge exported to JavaScript as `DeviceInfo`.
@interface DeviceInfoModule : NSObject <LynxModule>

@end

NS_ASSUME_NONNULL_END
