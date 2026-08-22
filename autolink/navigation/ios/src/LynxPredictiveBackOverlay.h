#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@class LynxContext;

NS_ASSUME_NONNULL_BEGIN

/** Passive native target; it never owns or registers a Back gesture. */
@protocol LynxPredictiveBackAnimationTarget <NSObject>

- (void)beginBackFromEdge:(NSString *)edge;
- (void)updateBackProgress:(CGFloat)progress edge:(NSString *)edge;
- (void)cancelBack;
- (void)commitBackWithCompletion:(dispatch_block_t)completion;

@end

FOUNDATION_EXPORT id<LynxPredictiveBackAnimationTarget> _Nullable
LynxPredictiveBackTargetForContext(LynxContext *context, NSString *targetID);

NS_ASSUME_NONNULL_END
