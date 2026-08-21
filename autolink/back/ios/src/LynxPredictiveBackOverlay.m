#import "LynxPredictiveBackOverlay.h"

#import <Lynx/LynxEvent.h>
#import <Lynx/LynxEventEmitter.h>
#import <Lynx/LynxContext.h>
#import <Lynx/LynxPropsProcessor.h>
#import <Lynx/LynxUIContext.h>
#import <Lynx/LynxUIView.h>
#import <QuartzCore/QuartzCore.h>

static NSString *const LynxBackMotionSheet = @"sheet";
static NSString *const LynxBackMotionHorizontal = @"horizontal";
static NSString *const LynxBackMotionNone = @"none";

static const NSTimeInterval LynxBackEnterDuration = 0.34;
static const NSTimeInterval LynxBackExitDuration = 0.26;
static const NSTimeInterval LynxBackSettleDuration = 0.22;

typedef NS_ENUM(NSInteger, LynxBackAnimationCurve) {
  LynxBackAnimationCurveEnter,
  LynxBackAnimationCurveExit,
  LynxBackAnimationCurveSettle,
};

@interface LynxPredictiveBackContainer
    : UIView <LynxPredictiveBackAnimationTarget, UIGestureRecognizerDelegate>

@property(nonatomic, strong) UIColor *backdropColor;
@property(nonatomic, copy) NSString *motion;
@property(nonatomic, copy, nullable) void (^transitionDidEnd)(BOOL presented);
@property(nonatomic, copy, nullable) dispatch_block_t dragDidDismiss;
@property(nonatomic, copy, nullable) dispatch_block_t backdropDidPress;

- (void)setPresented:(BOOL)presented;
- (void)setAnimatePresence:(BOOL)animated;
- (void)setDragToDismiss:(BOOL)enabled;
- (void)setDragDismissThreshold:(CGFloat)threshold;
- (void)setContentHeightRatio:(CGFloat)ratio;

- (void)dispose;

@end

@implementation LynxPredictiveBackContainer {
  CGFloat _progress;
  NSString *_edge;
  CADisplayLink *_displayLink;
  CFTimeInterval _animationStartTime;
  NSTimeInterval _animationDuration;
  CGFloat _animationStartProgress;
  CGFloat _animationTargetProgress;
  LynxBackAnimationCurve _animationCurve;
  dispatch_block_t _pendingCompletion;
  UIPanGestureRecognizer *_dismissPan;
  UITapGestureRecognizer *_backdropTap;
  BOOL _animatePresence;
  BOOL _dragToDismiss;
  BOOL _presented;
  BOOL _presentationResolved;
  BOOL _presentationPending;
  BOOL _dragSettling;
  CGFloat _dragDismissThreshold;
  CGFloat _contentHeightRatio;
}

- (instancetype)initWithFrame:(CGRect)frame {
  self = [super initWithFrame:frame];
  if (self) {
    _backdropColor = [UIColor colorWithWhite:0 alpha:0.45];
    _motion = LynxBackMotionSheet;
    _edge = @"left";
    _animatePresence = YES;
    _dragDismissThreshold = 0.22;
    self.userInteractionEnabled = YES;
    _dismissPan = [[UIPanGestureRecognizer alloc]
        initWithTarget:self
                action:@selector(handleDismissPan:)];
    _dismissPan.cancelsTouchesInView = YES;
    _dismissPan.delaysTouchesBegan = NO;
    _dismissPan.delegate = self;
    _dismissPan.enabled = NO;
    [self addGestureRecognizer:_dismissPan];
    _backdropTap = [[UITapGestureRecognizer alloc]
        initWithTarget:self
                action:@selector(handleBackdropTap:)];
    _backdropTap.cancelsTouchesInView = YES;
    _backdropTap.delaysTouchesBegan = NO;
    _backdropTap.delegate = self;
    [self addGestureRecognizer:_backdropTap];
    [self applyProgress:1];
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

- (void)setPresented:(BOOL)presented {
  if (_presentationResolved && _presented == presented) {
    return;
  }
  _presentationResolved = YES;
  _presented = presented;
  _presentationPending = YES;
  _dragSettling = NO;
  _dismissPan.enabled = _dragToDismiss;
  __weak LynxPredictiveBackContainer *weakSelf = self;
  dispatch_async(dispatch_get_main_queue(), ^{
    [weakSelf applyPendingPresentation];
  });
}

- (void)setAnimatePresence:(BOOL)animated {
  _animatePresence = animated;
}

- (void)setDragToDismiss:(BOOL)enabled {
  _dragToDismiss = enabled;
  _dismissPan.enabled = enabled;
  if (!enabled && _dragSettling) {
    _dragSettling = NO;
    [self animateToProgress:0
                   duration:LynxBackSettleDuration
                      curve:LynxBackAnimationCurveSettle
                 completion:nil];
  }
}

- (void)setDragDismissThreshold:(CGFloat)threshold {
  _dragDismissThreshold = MIN(MAX(threshold, 0.05), 0.9);
}

- (void)setContentHeightRatio:(CGFloat)ratio {
  _contentHeightRatio = MIN(MAX(ratio, 0), 1);
  [self applyProgress:_progress];
  if (_presentationPending && _contentHeightRatio > 0) {
    __weak LynxPredictiveBackContainer *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
      [weakSelf applyPendingPresentation];
    });
  }
}

- (void)didMoveToWindow {
  [super didMoveToWindow];
  if (_presentationPending) {
    [self applyPendingPresentation];
  }
}

- (void)layoutSubviews {
  [super layoutSubviews];
  [self applyProgress:_progress];
  if (_presentationPending) {
    [self applyPendingPresentation];
  }
}

- (void)beginBackFromEdge:(NSString *)edge {
  [self completePendingAnimation];
  _dragSettling = NO;
  _edge = [edge copy];
  [self applyProgress:0];
}

- (void)updateBackProgress:(CGFloat)progress edge:(NSString *)edge {
  _edge = [edge copy];
  [self applyProgress:progress];
}

- (void)cancelBack {
  [self abortPendingAnimation];
  [self animateToProgress:0
                 duration:LynxBackSettleDuration
                    curve:LynxBackAnimationCurveSettle
               completion:nil];
}

- (void)commitBackWithCompletion:(dispatch_block_t)completion {
  [self animateToProgress:1
                 duration:LynxBackSettleDuration
                    curve:LynxBackAnimationCurveSettle
               completion:completion];
}

- (void)dispose {
  [self completePendingAnimation];
  _presentationPending = NO;
  _dismissPan.enabled = NO;
  _backdropTap.enabled = NO;
  _transitionDidEnd = nil;
  _dragDidDismiss = nil;
  _backdropDidPress = nil;
  [self applyProgress:1];
}

- (void)applyPendingPresentation {
  if (!_presentationPending || self.window == nil ||
      CGRectIsEmpty(self.bounds) ||
      ([_motion isEqualToString:LynxBackMotionSheet] &&
       _contentHeightRatio <= 0)) {
    return;
  }
  _presentationPending = NO;
  [self abortPendingAnimation];
  BOOL targetPresented = _presented;
  CGFloat target = targetPresented ? 0 : 1;
  __weak LynxPredictiveBackContainer *weakSelf = self;
  dispatch_block_t completion = ^{
    LynxPredictiveBackContainer *strongSelf = weakSelf;
    if (strongSelf.transitionDidEnd != nil) {
      strongSelf.transitionDidEnd(targetPresented);
    }
  };
  if (!_animatePresence) {
    [self applyProgress:target];
    completion();
    return;
  }
  [self animateToProgress:target
                 duration:targetPresented ? LynxBackEnterDuration
                                          : LynxBackExitDuration
                    curve:targetPresented ? LynxBackAnimationCurveEnter
                                          : LynxBackAnimationCurveExit
               completion:completion];
}

- (void)animateToProgress:(CGFloat)target
                 duration:(NSTimeInterval)fullDuration
                    curve:(LynxBackAnimationCurve)curve
               completion:(nullable dispatch_block_t)completion {
  [self abortPendingAnimation];
  CGFloat start = _progress;
  if (fabs(start - target) < 0.001) {
    [self applyProgress:target];
    if (completion != nil) {
      completion();
    }
    return;
  }

  _pendingCompletion = [completion copy];
  _animationStartProgress = start;
  _animationTargetProgress = target;
  _animationDuration = MAX(0.08, fullDuration * fabs(target - start));
  _animationCurve = curve;
  _animationStartTime = CACurrentMediaTime();
  _displayLink = [CADisplayLink displayLinkWithTarget:self
                                             selector:@selector(stepAnimation:)];
  [_displayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}

- (void)stepAnimation:(CADisplayLink *)displayLink {
  CGFloat elapsed = displayLink.timestamp - _animationStartTime;
  CGFloat fraction = MIN(MAX(elapsed / _animationDuration, 0), 1);
  CGFloat eased = [self easedFraction:fraction curve:_animationCurve];
  [self applyProgress:_animationStartProgress +
                      (_animationTargetProgress - _animationStartProgress) *
                          eased];
  if (fraction >= 1) {
    [self applyProgress:_animationTargetProgress];
    [self completePendingAnimation];
  }
}

- (CGFloat)easedFraction:(CGFloat)value curve:(LynxBackAnimationCurve)curve {
  if (curve == LynxBackAnimationCurveEnter) {
    return 1 - pow(1 - value, 4);
  }
  if (curve == LynxBackAnimationCurveExit) {
    return value < 0.5 ? 4 * value * value * value
                       : 1 - pow(-2 * value + 2, 3) / 2;
  }
  return 1 - pow(1 - value, 3);
}

- (void)abortPendingAnimation {
  [_displayLink invalidate];
  _displayLink = nil;
  _pendingCompletion = nil;
}

- (void)completePendingAnimation {
  [_displayLink invalidate];
  _displayLink = nil;
  dispatch_block_t completion = _pendingCompletion;
  _pendingCompletion = nil;
  if (completion != nil) {
    completion();
  }
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
  if (gestureRecognizer == _backdropTap) {
    CGPoint location = [_backdropTap locationInView:self];
    return _presented && !_dragSettling && _displayLink == nil &&
           _progress <= 0.001 && ![self isPointInsideContent:location];
  }
  if (gestureRecognizer != _dismissPan || !_dragToDismiss || !_presented ||
      _dragSettling || _displayLink != nil ||
      ![_motion isEqualToString:LynxBackMotionSheet] || _progress > 0.001) {
    return NO;
  }
  CGPoint velocity = [_dismissPan velocityInView:self];
  if (velocity.y <= 0 || velocity.y <= fabs(velocity.x) * 1.05) {
    return NO;
  }
  CGPoint location = [_dismissPan locationInView:self];
  if (![self isPointInsideContent:location]) {
    return NO;
  }
  UIView *hitView = [self hitTest:location withEvent:nil];
  for (UIView *view = hitView; view != nil && view != self;
       view = view.superview) {
    if (![view isKindOfClass:UIScrollView.class]) {
      continue;
    }
    UIScrollView *scrollView = (UIScrollView *)view;
    if (scrollView.contentOffset.y > -scrollView.adjustedContentInset.top + 0.5) {
      return NO;
    }
  }
  return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
       shouldReceiveTouch:(UITouch *)touch {
  if (gestureRecognizer != _backdropTap) {
    return YES;
  }
  CGPoint location = [touch locationInView:self];
  return _presented && !_dragSettling && _displayLink == nil &&
         _progress <= 0.001 && ![self isPointInsideContent:location];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
    shouldRecognizeSimultaneouslyWithGestureRecognizer:
        (UIGestureRecognizer *)otherGestureRecognizer {
  return gestureRecognizer == _dismissPan || otherGestureRecognizer == _dismissPan;
}

- (void)handleDismissPan:(UIPanGestureRecognizer *)recognizer {
  if (recognizer.state == UIGestureRecognizerStateBegan) {
    [self abortPendingAnimation];
    _dragSettling = NO;
    return;
  }
  if (recognizer.state == UIGestureRecognizerStateChanged) {
    CGFloat distance = MAX(0, [recognizer translationInView:self].y);
    [self applyProgress:distance / MAX([self contentTravelHeight], 1)];
    return;
  }
  if (recognizer.state != UIGestureRecognizerStateEnded &&
      recognizer.state != UIGestureRecognizerStateCancelled &&
      recognizer.state != UIGestureRecognizerStateFailed) {
    return;
  }

  CGFloat velocityY = [recognizer velocityInView:self].y;
  BOOL shouldDismiss =
      recognizer.state == UIGestureRecognizerStateEnded &&
      (_progress >= _dragDismissThreshold ||
       (_progress >= 0.04 && velocityY >= 900));
  _dragSettling = YES;
  __weak LynxPredictiveBackContainer *weakSelf = self;
  if (shouldDismiss) {
    [self animateToProgress:1
                   duration:LynxBackExitDuration
                      curve:LynxBackAnimationCurveExit
                 completion:^{
                   LynxPredictiveBackContainer *strongSelf = weakSelf;
                   if (strongSelf == nil) {
                     return;
                   }
                   strongSelf->_dragSettling = NO;
                   if (strongSelf.dragDidDismiss != nil) {
                     strongSelf.dragDidDismiss();
                   }
                 }];
  } else {
    [self animateToProgress:0
                   duration:LynxBackSettleDuration
                      curve:LynxBackAnimationCurveSettle
                 completion:^{
                   LynxPredictiveBackContainer *strongSelf = weakSelf;
                   if (strongSelf != nil) {
                     strongSelf->_dragSettling = NO;
                   }
                 }];
  }
}

- (void)handleBackdropTap:(UITapGestureRecognizer *)recognizer {
  if (recognizer.state == UIGestureRecognizerStateRecognized &&
      self.backdropDidPress != nil) {
    self.backdropDidPress();
  }
}

- (BOOL)isPointInsideContent:(CGPoint)point {
  CGFloat contentHeight = [self contentTravelHeight];
  return point.y >= MAX(0, self.bounds.size.height - contentHeight);
}

- (CGFloat)contentTravelHeight {
  if (_contentHeightRatio > 0) {
    return self.bounds.size.height * _contentHeightRatio;
  }
  CGFloat contentHeight = 0;
  for (UIView *subview in self.subviews) {
    contentHeight = MAX(contentHeight, subview.bounds.size.height);
  }
  return contentHeight > 0 ? contentHeight : self.bounds.size.height;
}

- (void)applyProgress:(CGFloat)value {
  _progress = MIN(MAX(value, 0), 1);
  CGFloat translationX = 0;
  CGFloat translationY = 0;
  if ([_motion isEqualToString:LynxBackMotionHorizontal]) {
    CGFloat direction = [_edge isEqualToString:@"right"] ? -1 : 1;
    translationX = self.bounds.size.width * _progress * direction;
  } else if (![_motion isEqualToString:LynxBackMotionNone]) {
    translationY = [self contentTravelHeight] * _progress;
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

- (void)emitTransitionEnd:(BOOL)presented;
- (void)emitDragDismiss;
- (void)emitBackdropPress;

@end

@LynxElement("predictive-back-overlay")
@implementation LynxUIPredictiveBackOverlay {
  NSString *_targetID;
  __weak LynxContext *_registeredContext;
}

- (UIView *)createView {
  LynxPredictiveBackContainer *container =
      [[LynxPredictiveBackContainer alloc] init];
  __weak LynxUIPredictiveBackOverlay *weakSelf = self;
  container.transitionDidEnd = ^(BOOL presented) {
    [weakSelf emitTransitionEnd:presented];
  };
  container.dragDidDismiss = ^{
    [weakSelf emitDragDismiss];
  };
  container.backdropDidPress = ^{
    [weakSelf emitBackdropPress];
  };
  return container;
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

LYNX_PROP_SETTER("presented", setPresented, BOOL) {
  LynxPredictiveBackContainer *target =
      (LynxPredictiveBackContainer *)self.view;
  [target setPresented:requestReset ? NO : value];
}

LYNX_PROP_SETTER("animate-presence", setAnimatePresence, BOOL) {
  LynxPredictiveBackContainer *target =
      (LynxPredictiveBackContainer *)self.view;
  [target setAnimatePresence:requestReset ? YES : value];
}

LYNX_PROP_SETTER("drag-to-dismiss", setDragToDismiss, BOOL) {
  LynxPredictiveBackContainer *target =
      (LynxPredictiveBackContainer *)self.view;
  [target setDragToDismiss:requestReset ? NO : value];
}

LYNX_PROP_SETTER("drag-dismiss-threshold", setDragDismissThreshold, CGFloat) {
  LynxPredictiveBackContainer *target =
      (LynxPredictiveBackContainer *)self.view;
  [target setDragDismissThreshold:requestReset ? 0.22 : value];
}

LYNX_PROP_SETTER("content-height-ratio", setContentHeightRatio, CGFloat) {
  LynxPredictiveBackContainer *target =
      (LynxPredictiveBackContainer *)self.view;
  [target setContentHeightRatio:requestReset ? 0 : value];
}

- (void)emitTransitionEnd:(BOOL)presented {
  LynxDetailEvent *event =
      [[LynxDetailEvent alloc] initWithName:@"overlaytransitionend"
                                targetSign:self.sign
                                    detail:@{ @"presented" : @(presented) }];
  [self.context.eventEmitter dispatchCustomEvent:event];
}

- (void)emitDragDismiss {
  LynxDetailEvent *event =
      [[LynxDetailEvent alloc] initWithName:@"dragdismiss"
                                targetSign:self.sign
                                    detail:@{}];
  [self.context.eventEmitter dispatchCustomEvent:event];
}

- (void)emitBackdropPress {
  LynxDetailEvent *event =
      [[LynxDetailEvent alloc] initWithName:@"backdroppress"
                                targetSign:self.sign
                                    detail:@{}];
  [self.context.eventEmitter dispatchCustomEvent:event];
}

- (void)dealloc {
  LynxPredictiveBackContainer *target =
      (LynxPredictiveBackContainer *)self.view;
  LynxUnregisterBackTarget(_registeredContext, _targetID, target);
  [target dispose];
}

@end
