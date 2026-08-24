#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Normalizes orientation, optionally mirrors, writes a cache JPEG and returns
/// the cross-platform metadata dictionary used by CameraModule/x-camera-view.
FOUNDATION_EXPORT NSDictionary<NSString *, id> *_Nullable
LynxCameraWriteJPEG(UIImage *image,
                    CGFloat quality,
                    BOOL mirrorHorizontally,
                    NSError **error);

NS_ASSUME_NONNULL_END
