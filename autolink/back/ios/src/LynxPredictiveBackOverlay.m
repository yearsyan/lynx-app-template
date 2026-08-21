#import "LynxPredictiveBackOverlay.h"

#import <Lynx/LynxContext.h>
#import <Lynx/LynxPropsProcessor.h>
#import <Lynx/LynxUIContext.h>
#import <Lynx/LynxUIView.h>

static NSString *const LynxBackMotionSheet = @"sheet";
static NSString *const LynxBackMotionHorizontal = @"horizontal";
static NSString *const LynxBackMotionNone = @"none";

@interface LynxPredictiveBackContainer
    : UIView <LynxPredictiveBackAnimationTarget>

@property(nonatomic, strong) UIColor *backdropColor;
@property(nonatomic, copy) NSString *motion;

- (void)dispose;

@end

@implementation LynxPredictiveBackContainer {
  CGFloat _progress;
  NSString *_edge;
  NSUInteger _animationGeneration;
  dispatch_block_t _pendingCompletion;
}

- (instancetype)initWithFrame:(CGRect)frame {
  self = [super initWithFrame:frame];
  if (self) {
    _backdropColor = [UIColor colorWithWhite:0 alpha:0.45];
    _motion = LynxBackMotionSheet;
    _edge = @"left";
    self.userInteractionEnabled = YES;
    [self applyProgress:0];
  }
  return self;
}

- (void)setBackdropColor:(UIColor *)backdropColor {
  _backdropColor = backdropColor ?: UIColor.clearColor;
  [self applyProgress:_progress];
}

- (void)setMotion:(NSString *)motion {
  if ([motion isEqualToString:LynxBackMotionHorizontal] ||
      [motion isEqualToString:LynxBackMotionNone]) {
    _motion = [motion copy];
  } else {
    _motion = LynxBackMotionSheet;
  }
  [self applyProgress:_progress];
}

- (void)beginBackFromEdge:(NSString *)edge {
  [self completePendingAnimation];
  [self.layer removeAllAnimations];
  _edge = [edge copy];
  [self applyProgress:0];
}

- (void)updateBackProgress:(CGFloat)progress edge:(NSString *)edge {
  _edge = [edge copy];
  [self applyProgress:progress];
}

- (void)cancelBack {
  [self abortPendingAnimation];
  [self animateToProgress:0 completion:nil];
}

- (void)commitBackWithCompletion:(dispatch_block_t)completion {
  [self animateToProgress:1 completion:completion];
}

- (void)dispose {
  [self completePendingAnimation];
  [self.layer removeAllAnimations];
  [self applyProgress:0];
}

- (void)animateToProgress:(CGFloat)target
               completion:(nullable dispatch_block_t)completion {
  [self abortPendingAnimation];
  [self.layer removeAllAnimations];
  CGFloat start = _progress;
  if (fabs(start - target) < 0.001) {
    [self applyProgress:target];
    if (completion != nil) {
      completion();
    }
    return;
  }

  NSUInteger generation = ++_animationGeneration;
  _pendingCompletion = [completion copy];
  NSTimeInterval duration = 0.10 + 0.10 * fabs(target - start);
  [UIView animateWithDuration:duration
      delay:0
      options:UIViewAnimationOptionBeginFromCurrentState |
              UIViewAnimationOptionCurveEaseOut |
              UIViewAnimationOptionAllowUserInteraction
      animations:^{
        [self applyProgress:target];
      }
      completion:^(__unused BOOL finished) {
        if (generation != self->_animationGeneration) {
          return;
        }
        [self completePendingAnimation];
      }];
}

- (void)abortPendingAnimation {
  _animationGeneration += 1;
  _pendingCompletion = nil;
  [self.layer removeAllAnimations];
}

- (void)completePendingAnimation {
  _animationGeneration += 1;
  dispatch_block_t completion = _pendingCompletion;
  _pendingCompletion = nil;
  if (completion != nil) {
    completion();
  }
}

- (void)applyProgress:(CGFloat)value {
  _progress = MIN(MAX(value, 0), 1);
  CGFloat translationX = 0;
  CGFloat translationY = 0;
  if ([_motion isEqualToString:LynxBackMotionHorizontal]) {
    CGFloat direction = [_edge isEqualToString:@"right"] ? -1 : 1;
    translationX = self.bounds.size.width * _progress * direction;
  } else if (![_motion isEqualToString:LynxBackMotionNone]) {
    CGFloat contentHeight = 0;
    for (UIView *subview in self.subviews) {
      contentHeight = MAX(contentHeight, subview.bounds.size.height);
    }
    translationY = (contentHeight > 0 ? contentHeight : self.bounds.size.height) *
                   _progress;
  }
  self.layer.sublayerTransform =
      CATransform3DMakeTranslation(translationX, translationY, 0);
  self.backgroundColor =
      [_backdropColor colorWithAlphaComponent:CGColorGetAlpha(
                                                  _backdropColor.CGColor) *
                                              (1 - _progress)];
}

@end

static NSMapTable<LynxContext *, NSMapTable<NSString *, LynxPredictiveBackContainer *> *> *
    LynxBackTargets(void) {
  static NSMapTable *targets;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    targets = [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsWeakMemory
                                    valueOptions:NSPointerFunctionsStrongMemory];
  });
  return targets;
}

static void LynxRegisterBackTarget(LynxContext *context,
                                   NSString *targetID,
                                   LynxPredictiveBackContainer *target) {
  if (context == nil || targetID.length == 0 || target == nil) {
    return;
  }
  NSMapTable *contextTargets = [LynxBackTargets() objectForKey:context];
  if (contextTargets == nil) {
    contextTargets = [NSMapTable
        mapTableWithKeyOptions:NSPointerFunctionsStrongMemory
                  valueOptions:NSPointerFunctionsWeakMemory];
    [LynxBackTargets() setObject:contextTargets forKey:context];
  }
  [contextTargets setObject:target forKey:targetID];
}

static void LynxUnregisterBackTarget(LynxContext *context,
                                     NSString *targetID,
                                     LynxPredictiveBackContainer *target) {
  if (context == nil || targetID.length == 0 || target == nil) {
    return;
  }
  NSMapTable *contextTargets = [LynxBackTargets() objectForKey:context];
  if ([contextTargets objectForKey:targetID] == target) {
    [contextTargets removeObjectForKey:targetID];
  }
  if (contextTargets.count == 0) {
    [LynxBackTargets() removeObjectForKey:context];
  }
}

id<LynxPredictiveBackAnimationTarget> LynxPredictiveBackTargetForContext(
    LynxContext *context, NSString *targetID) {
  if (context == nil || targetID.length == 0) {
    return nil;
  }
  LynxPredictiveBackContainer *target =
      [[LynxBackTargets() objectForKey:context] objectForKey:targetID];
  return target.window == nil ? nil : target;
}

@interface LynxUIPredictiveBackOverlay : LynxUIView
@end

@LynxElement("predictive-back-overlay")
@implementation LynxUIPredictiveBackOverlay {
  NSString *_targetID;
  __weak LynxContext *_registeredContext;
}

- (UIView *)createView {
  return [[LynxPredictiveBackContainer alloc] init];
}

LYNX_PROP_SETTER("target-id", setTargetID, NSString *) {
  LynxPredictiveBackContainer *target =
      (LynxPredictiveBackContainer *)self.view;
  LynxUnregisterBackTarget(_registeredContext, _targetID, target);
  _targetID = requestReset ? @"" : [value copy];
  _registeredContext = self.context.lynxContext;
  LynxRegisterBackTarget(_registeredContext, _targetID, target);
}

LYNX_PROP_SETTER("backdrop-color", setBackdropColor, UIColor *) {
  LynxPredictiveBackContainer *target =
      (LynxPredictiveBackContainer *)self.view;
  target.backdropColor =
      requestReset ? [UIColor colorWithWhite:0 alpha:0.45] : value;
}

LYNX_PROP_SETTER("motion", setMotion, NSString *) {
  LynxPredictiveBackContainer *target =
      (LynxPredictiveBackContainer *)self.view;
  target.motion = requestReset ? LynxBackMotionSheet : value;
}

- (void)dealloc {
  LynxPredictiveBackContainer *target =
      (LynxPredictiveBackContainer *)self.view;
  LynxUnregisterBackTarget(_registeredContext, _targetID, target);
  [target dispose];
}

@end
