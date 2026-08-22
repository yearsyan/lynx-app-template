#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

#import <Lynx/LynxColorUtils.h>
#import <Lynx/LynxEvent.h>
#import <Lynx/LynxEventEmitter.h>
#import <Lynx/LynxPropsProcessor.h>
#import <Lynx/LynxUIView.h>

static const CGFloat kDefaultActiveOpacity = 0.7;
static const NSTimeInterval kPressDelay = 0.06;
static const NSTimeInterval kMinimumTapFlash = 0.072;
static const NSTimeInterval kLongPressDuration = 0.5;
static const NSTimeInterval kScrollCooldown = 0.12;
static const CGFloat kTouchSlop = 10.0;
static void *kPressableScrollOffsetContext = &kPressableScrollOffsetContext;

@class LynxUIPressableView;

@interface LynxPressableContainer : UIView <UIGestureRecognizerDelegate>

@property(nonatomic, weak) LynxUIPressableView *owner;
@property(nonatomic, assign) CGFloat activeOpacity;
@property(nonatomic, strong) UIColor *pressedOverlayColor;
@property(nonatomic, assign, getter=isPressDisabled) BOOL pressDisabled;
@property(nonatomic, assign) BOOL longPressHapticEnabled;

- (void)cancelPress;
- (void)flashForAccessibility;

@end

@interface LynxUIPressableView : LynxUIView

- (void)emitPress;

@end

@implementation LynxPressableContainer {
  BOOL _trackingPress;
  BOOL _blocked;
  BOOL _pressVisualVisible;
  BOOL _longPressRecognized;
  CGFloat _baseAlpha;
  CGPoint _downPoint;
  NSUInteger _sequence;
  UILongPressGestureRecognizer *_pressRecognizer;
  NSMutableArray<UIScrollView *> *_observedScrollViews;
  CFTimeInterval _lastScrollActivityTime;
  UIView *_pressedOverlayView;
  UIImpactFeedbackGenerator *_longPressFeedbackGenerator;
}

- (instancetype)initWithFrame:(CGRect)frame {
  self = [super initWithFrame:frame];
  if (self) {
    _activeOpacity = kDefaultActiveOpacity;
    _baseAlpha = 1.0;
    _observedScrollViews = [NSMutableArray array];
    self.userInteractionEnabled = YES;
    self.multipleTouchEnabled = NO;
    self.isAccessibilityElement = YES;
    self.accessibilityTraits = UIAccessibilityTraitButton;

    _pressedOverlayColor = UIColor.clearColor;
    _pressedOverlayView = [[UIView alloc] initWithFrame:self.bounds];
    _pressedOverlayView.autoresizingMask =
        UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _pressedOverlayView.backgroundColor = _pressedOverlayColor;
    _pressedOverlayView.hidden = YES;
    _pressedOverlayView.userInteractionEnabled = NO;
    _pressedOverlayView.accessibilityElementsHidden = YES;
    [self addSubview:_pressedOverlayView];

    _pressRecognizer = [[UILongPressGestureRecognizer alloc]
        initWithTarget:self
                action:@selector(handlePressGesture:)];
    _pressRecognizer.minimumPressDuration = 0;
    _pressRecognizer.allowableMovement = CGFLOAT_MAX;
    _pressRecognizer.cancelsTouchesInView = NO;
    _pressRecognizer.delaysTouchesBegan = NO;
    _pressRecognizer.delegate = self;
    [self addGestureRecognizer:_pressRecognizer];
  }
  return self;
}

- (void)layoutSubviews {
  [super layoutSubviews];
  _pressedOverlayView.frame = self.bounds;
  _pressedOverlayView.layer.cornerRadius = self.layer.cornerRadius;
  _pressedOverlayView.layer.maskedCorners = self.layer.maskedCorners;
  [self bringSubviewToFront:_pressedOverlayView];
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
  if (self.pressDisabled || self.hidden || !self.userInteractionEnabled ||
      ![self pointInside:point withEvent:event]) {
    return nil;
  }
  // The element intentionally behaves as one whole-item target. Returning
  // self also lets UIScrollView cancel it as a regular content UIView.
  return self;
}

- (void)setAlpha:(CGFloat)alpha {
  _baseAlpha = alpha;
  [self applyCombinedAlpha];
}

- (void)setActiveOpacity:(CGFloat)activeOpacity {
  _activeOpacity = MIN(1.0, MAX(0.0, activeOpacity));
  [self applyCombinedAlpha];
}

- (void)setPressedOverlayColor:(UIColor *)pressedOverlayColor {
  _pressedOverlayColor = pressedOverlayColor ?: UIColor.clearColor;
  _pressedOverlayView.backgroundColor = _pressedOverlayColor;
  [self applyPressedOverlay];
}

- (void)setPressDisabled:(BOOL)pressDisabled {
  _pressDisabled = pressDisabled;
  self.userInteractionEnabled = !pressDisabled;
  _pressRecognizer.enabled = !pressDisabled;
  self.accessibilityTraits = pressDisabled
                                 ? UIAccessibilityTraitButton |
                                       UIAccessibilityTraitNotEnabled
                                 : UIAccessibilityTraitButton;
  if (pressDisabled) {
    [self cancelPress];
  }
}

- (void)setLongPressHapticEnabled:(BOOL)longPressHapticEnabled {
  _longPressHapticEnabled = longPressHapticEnabled;
  if (!longPressHapticEnabled) {
    _longPressFeedbackGenerator = nil;
  }
}

- (void)didMoveToWindow {
  [super didMoveToWindow];
  if (self.window == nil) {
    [self detachScrollObservers];
    [self cancelPress];
  } else {
    [self refreshScrollObservers];
  }
}

- (void)didMoveToSuperview {
  [super didMoveToSuperview];
  if (self.window != nil) {
    [self refreshScrollObservers];
  }
}

- (void)dealloc {
  [self detachScrollObservers];
}

- (void)handlePressGesture:(UILongPressGestureRecognizer *)recognizer {
  CGPoint point = [recognizer locationInView:self];
  switch (recognizer.state) {
    case UIGestureRecognizerStateBegan:
      [self beginPressAtPoint:point];
      break;
    case UIGestureRecognizerStateChanged:
      [self updatePressAtPoint:point];
      break;
    case UIGestureRecognizerStateEnded:
      [self finishPressAtPoint:point];
      break;
    case UIGestureRecognizerStateCancelled:
    case UIGestureRecognizerStateFailed:
      [self cancelPress];
      break;
    default:
      break;
  }
}

- (void)beginPressAtPoint:(CGPoint)point {
  if (self.pressDisabled) {
    return;
  }

  _sequence += 1;
  _trackingPress = YES;
  _blocked = [self ancestorScrollIsActive];
  _longPressRecognized = NO;
  _downPoint = point;
  [self setPressVisual:NO];

  if (_blocked) {
    return;
  }

  if (self.longPressHapticEnabled) {
    _longPressFeedbackGenerator =
        [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [_longPressFeedbackGenerator prepare];
  }

  NSUInteger sequence = _sequence;
  __weak typeof(self) weakSelf = self;
  dispatch_after(
      dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kPressDelay * NSEC_PER_SEC)),
      dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil || sequence != strongSelf->_sequence ||
            !strongSelf->_trackingPress || strongSelf->_blocked ||
            [strongSelf ancestorScrollIsActive]) {
          return;
        }
        [strongSelf setPressVisual:YES];
      });

  dispatch_after(
      dispatch_time(DISPATCH_TIME_NOW,
                    (int64_t)(kLongPressDuration * NSEC_PER_SEC)),
      dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil || sequence != strongSelf->_sequence ||
            !strongSelf->_trackingPress || strongSelf->_blocked ||
            strongSelf.isPressDisabled ||
            [strongSelf ancestorScrollIsActive]) {
          return;
        }
        strongSelf->_longPressRecognized = YES;
        [strongSelf setPressVisual:YES];
        if (strongSelf.longPressHapticEnabled) {
          [strongSelf->_longPressFeedbackGenerator impactOccurred];
        }
        strongSelf->_longPressFeedbackGenerator = nil;
      });
}

- (void)updatePressAtPoint:(CGPoint)point {
  if (!_trackingPress || _blocked) {
    return;
  }
  CGFloat deltaX = point.x - _downPoint.x;
  CGFloat deltaY = point.y - _downPoint.y;
  if (hypot(deltaX, deltaY) > kTouchSlop ||
      ![self pointInsideRetentionBounds:point] || [self ancestorScrollIsActive]) {
    [self blockCurrentSequence];
  }
}

- (void)finishPressAtPoint:(CGPoint)point {
  BOOL accepted = _trackingPress && !_blocked && !self.pressDisabled &&
                  [self pointInsideRetentionBounds:point] &&
                  ![self ancestorScrollIsActive];
  BOOL completedLongPress = accepted && _longPressRecognized;
  BOOL visualWasVisible = _pressVisualVisible;

  _trackingPress = NO;
  _blocked = NO;
  _longPressRecognized = NO;
  _longPressFeedbackGenerator = nil;
  _sequence += 1;

  if (!accepted) {
    [self setPressVisual:NO];
    return;
  }

  if (completedLongPress) {
    [self setPressVisual:NO];
    return;
  }

  if (visualWasVisible) {
    [self setPressVisual:NO];
  } else {
    [self showMinimumTapFlash];
  }
  [self.owner emitPress];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
    shouldRecognizeSimultaneouslyWithGestureRecognizer:
        (UIGestureRecognizer *)otherGestureRecognizer {
  // Never make the press recognizer an obstacle for Lynx or UIScrollView.
  // Movement and scroll state latch this sequence as blocked instead.
  return YES;
}

- (BOOL)accessibilityActivate {
  if (self.pressDisabled) {
    return NO;
  }
  [self flashForAccessibility];
  [self.owner emitPress];
  return YES;
}

- (void)flashForAccessibility {
  [self showMinimumTapFlash];
}

- (void)showMinimumTapFlash {
  NSUInteger sequence = ++_sequence;
  [self setPressVisual:YES];
  __weak typeof(self) weakSelf = self;
  dispatch_after(
      dispatch_time(DISPATCH_TIME_NOW,
                    (int64_t)(kMinimumTapFlash * NSEC_PER_SEC)),
      dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf != nil && sequence == strongSelf->_sequence &&
            !strongSelf->_trackingPress) {
          [strongSelf setPressVisual:NO];
        }
      });
}

- (void)blockCurrentSequence {
  _blocked = YES;
  _longPressFeedbackGenerator = nil;
  _sequence += 1;
  [self setPressVisual:NO];
}

- (void)cancelPress {
  _trackingPress = NO;
  _blocked = NO;
  _longPressRecognized = NO;
  _longPressFeedbackGenerator = nil;
  _sequence += 1;
  [self setPressVisual:NO];
}

- (BOOL)pointInsideRetentionBounds:(CGPoint)point {
  return CGRectContainsPoint(CGRectInset(self.bounds, -kTouchSlop, -kTouchSlop),
                             point);
}

- (BOOL)ancestorScrollIsActive {
  UIView *ancestor = self.superview;
  while (ancestor != nil) {
    if ([ancestor isKindOfClass:UIScrollView.class]) {
      UIScrollView *scrollView = (UIScrollView *)ancestor;
      UIGestureRecognizerState panState = scrollView.panGestureRecognizer.state;
      if (scrollView.dragging || scrollView.decelerating ||
          panState == UIGestureRecognizerStateBegan ||
          panState == UIGestureRecognizerStateChanged) {
        return YES;
      }
    }
    ancestor = ancestor.superview;
  }
  return _lastScrollActivityTime > 0 &&
         CACurrentMediaTime() - _lastScrollActivityTime <= kScrollCooldown;
}

- (void)refreshScrollObservers {
  [self detachScrollObservers];
  _lastScrollActivityTime = 0;

  UIView *ancestor = self.superview;
  while (ancestor != nil) {
    if ([ancestor isKindOfClass:UIScrollView.class]) {
      UIScrollView *scrollView = (UIScrollView *)ancestor;
      [scrollView addObserver:self
                   forKeyPath:@"contentOffset"
                      options:0
                      context:kPressableScrollOffsetContext];
      [_observedScrollViews addObject:scrollView];
    }
    ancestor = ancestor.superview;
  }
}

- (void)detachScrollObservers {
  for (UIScrollView *scrollView in _observedScrollViews) {
    [scrollView removeObserver:self
                    forKeyPath:@"contentOffset"
                       context:kPressableScrollOffsetContext];
  }
  [_observedScrollViews removeAllObjects];
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey, id> *)change
                       context:(void *)context {
  if (context != kPressableScrollOffsetContext) {
    [super observeValueForKeyPath:keyPath
                         ofObject:object
                           change:change
                          context:context];
    return;
  }

  _lastScrollActivityTime = CACurrentMediaTime();
  if (_trackingPress) {
    [self blockCurrentSequence];
  }
}

- (void)setPressVisual:(BOOL)visible {
  if (_pressVisualVisible == visible) {
    return;
  }
  _pressVisualVisible = visible;
  [self applyCombinedAlpha];
  [self applyPressedOverlay];
}

- (void)applyCombinedAlpha {
  CGFloat multiplier = _pressVisualVisible ? self.activeOpacity : 1.0;
  [super setAlpha:_baseAlpha * multiplier];
}

- (void)applyPressedOverlay {
  _pressedOverlayView.hidden =
      !_pressVisualVisible || CGColorGetAlpha(self.pressedOverlayColor.CGColor) <= 0;
}

@end

@LynxElement("pressable-view")
@implementation LynxUIPressableView

- (UIView *)createView {
  LynxPressableContainer *container = [[LynxPressableContainer alloc] init];
  container.owner = self;
  container.translatesAutoresizingMaskIntoConstraints = YES;
  return container;
}

LYNX_PROP_SETTER("active-opacity", setActiveOpacity, CGFloat) {
  LynxPressableContainer *container = (LynxPressableContainer *)self.view;
  container.activeOpacity = requestReset ? kDefaultActiveOpacity : value;
}

LYNX_PROP_SETTER("pressed-overlay-color", setPressedOverlayColor, NSString *) {
  LynxPressableContainer *container = (LynxPressableContainer *)self.view;
  UIColor *color = requestReset
                       ? UIColor.clearColor
                       : [LynxColorUtils convertNSStringToUIColor:value];
  container.pressedOverlayColor = color ?: UIColor.clearColor;
}

LYNX_PROP_SETTER("disabled", setDisabled, BOOL) {
  LynxPressableContainer *container = (LynxPressableContainer *)self.view;
  container.pressDisabled = requestReset ? NO : value;
}

LYNX_PROP_SETTER("long-press-haptic", setLongPressHaptic, BOOL) {
  LynxPressableContainer *container = (LynxPressableContainer *)self.view;
  container.longPressHapticEnabled = requestReset ? NO : value;
}

- (void)emitPress {
  if (((LynxPressableContainer *)self.view).isPressDisabled) {
    return;
  }
  LynxDetailEvent *event =
      [[LynxDetailEvent alloc] initWithName:@"press"
                                targetSign:self.sign
                                    detail:@{}];
  [self.context.eventEmitter dispatchCustomEvent:event];
}

- (void)dealloc {
  LynxPressableContainer *container = (LynxPressableContainer *)self.view;
  [container cancelPress];
  container.owner = nil;
}

@end
