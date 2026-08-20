#import "BackModule.h"

#import <Lynx/LynxContext.h>
#import <Lynx/LynxView.h>

static NSString *const LynxBackEventName = @"back";

/** Child controller that mirrors its owning page's appearance lifecycle. */
@interface LynxBackLifecycleObserver : UIViewController

@property(nonatomic, copy, nullable) void (^visibilityDidChange)(BOOL visible);

@end


@implementation LynxBackLifecycleObserver

- (void)viewDidAppear:(BOOL)animated {
  [super viewDidAppear:animated];
  if (self.visibilityDidChange != nil) {
    self.visibilityDidChange(YES);
  }
}

- (void)viewWillDisappear:(BOOL)animated {
  if (self.visibilityDidChange != nil) {
    self.visibilityDidChange(NO);
  }
  [super viewWillDisappear:animated];
}

@end


// The @LynxNativeModule annotation is what cocoapods-lynx-library scans for;
// it expands to a harmless ObjC forward declaration when compiled.
@LynxNativeModule("Back")
@implementation BackModule {
  __weak LynxContext *_lynxContext;
  __weak UIViewController *_host;
  __weak UIGestureRecognizer *_capturedNativePopGesture;
  NSNumber *_nativePopWasEnabled;
  NSArray<UIBarButtonItem *> *_savedLeftBarButtonItems;
  NSNumber *_savedHidesBackButton;
  LynxBackLifecycleObserver *_lifecycleObserver;
  UIScreenEdgePanGestureRecognizer *_edgeGesture;
  BOOL _installedBackButton;
  BOOL _enabled;
  BOOL _visible;
  BOOL _gestureStarted;
  BOOL _destroyed;
  CGFloat _lastProgress;
  CGPoint _lastTouch;
}

+ (NSString *)name {
  return @"Back";
}

+ (NSDictionary<NSString *, NSString *> *)methodLookup {
  return @{
    @"setEnabled" : NSStringFromSelector(@selector(setEnabled:callback:)),
  };
}

- (instancetype)initWithLynxContext:(LynxContext *)context {
  self = [super init];
  if (self) {
    _lynxContext = context;
    _edgeGesture = [[UIScreenEdgePanGestureRecognizer alloc]
        initWithTarget:self
                action:@selector(handleEdgeGesture:)];
    _edgeGesture.cancelsTouchesInView = YES;
    _edgeGesture.delegate = self;
    _edgeGesture.enabled = NO;
  }
  return self;
}

- (void)setEnabled:(BOOL)enabled callback:(LynxCallbackBlock)callback {
  dispatch_async(dispatch_get_main_queue(), ^{
    if (self->_destroyed) {
      callback(@"Back has already been destroyed");
      return;
    }
    if (enabled && ![self attachToCurrentHost]) {
      callback(@"Back has no UIViewController host");
      return;
    }
    if (!enabled && self->_gestureStarted) {
      [self emitPhase:@"cancel"
             progress:self->_lastProgress
               source:@"gesture"
                touch:self->_lastTouch
                 edge:nil];
      [self resetGesture];
    }
    self->_enabled = enabled;
    [self updateInterception];
    callback(@"");
  });
}

- (void)destroy {
  dispatch_async(dispatch_get_main_queue(), ^{
    if (self->_destroyed) {
      return;
    }
    self->_destroyed = YES;
    if (self->_gestureStarted) {
      [self emitPhase:@"cancel"
             progress:self->_lastProgress
               source:@"gesture"
                touch:self->_lastTouch
                 edge:nil];
    }
    self->_enabled = NO;
    self->_visible = NO;
    [self resetGesture];
    [self updateInterception];
    [self detachFromHost];
    self->_lynxContext = nil;
  });
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
  UIViewController *host = _host;
  return _enabled && _visible && host != nil &&
         host.viewIfLoaded.window != nil && host.transitionCoordinator == nil;
}

- (BOOL)attachToCurrentHost {
  UIViewController *host = [self hostingViewController];
  if (host == nil) {
    return NO;
  }
  if (_host == host && _edgeGesture.view != nil) {
    return YES;
  }

  [self detachFromHost];
  _host = host;
  [self updateGestureEdgeForView:host.view];
  [host.view addGestureRecognizer:_edgeGesture];

  LynxBackLifecycleObserver *observer = [[LynxBackLifecycleObserver alloc] init];
  __weak BackModule *weakSelf = self;
  observer.visibilityDidChange = ^(BOOL visible) {
    BackModule *strongSelf = weakSelf;
    if (strongSelf == nil || strongSelf->_destroyed) {
      return;
    }
    strongSelf->_visible = visible;
    [strongSelf updateInterception];
  };
  [host addChildViewController:observer];
  observer.view.hidden = YES;
  observer.view.userInteractionEnabled = NO;
  observer.view.frame = CGRectZero;
  [host.view addSubview:observer.view];
  [observer didMoveToParentViewController:host];
  _lifecycleObserver = observer;

  _visible = host.viewIfLoaded.window != nil;
  [self updateInterception];
  return YES;
}

- (void)detachFromHost {
  [self restoreNativeInteractivePop];
  [self restoreNavigationButton];
  _edgeGesture.enabled = NO;
  [_edgeGesture.view removeGestureRecognizer:_edgeGesture];

  LynxBackLifecycleObserver *observer = _lifecycleObserver;
  observer.visibilityDidChange = nil;
  if (observer.parentViewController != nil) {
    [observer willMoveToParentViewController:nil];
    [observer.view removeFromSuperview];
    [observer removeFromParentViewController];
  }
  _lifecycleObserver = nil;
  _visible = NO;
  _host = nil;
}

- (nullable UIViewController *)hostingViewController {
  UIResponder *responder = [_lynxContext getLynxView];
  while (responder != nil && ![responder isKindOfClass:UIViewController.class]) {
    responder = responder.nextResponder;
  }
  return (UIViewController *)responder;
}

- (void)updateInterception {
  UIViewController *host = _host;
  if (host == nil) {
    return;
  }
  BOOL shouldIntercept = _enabled && _visible;
  [self updateGestureEdgeForView:host.view];
  _edgeGesture.enabled = shouldIntercept;
  if (shouldIntercept) {
    [self suspendNativeInteractivePopIfNeeded];
    [self installNavigationButtonIfNeeded];
  } else {
    [self restoreNativeInteractivePop];
    [self restoreNavigationButton];
  }
}

- (void)updateGestureEdgeForView:(UIView *)view {
  UIUserInterfaceLayoutDirection direction =
      [UIView userInterfaceLayoutDirectionForSemanticContentAttribute:
                  view.semanticContentAttribute];
  _edgeGesture.edges = direction == UIUserInterfaceLayoutDirectionRightToLeft
                           ? UIRectEdgeRight
                           : UIRectEdgeLeft;
}

- (void)suspendNativeInteractivePopIfNeeded {
  UIGestureRecognizer *gesture =
      _host.navigationController.interactivePopGestureRecognizer;
  if (gesture == nil) {
    [self restoreNativeInteractivePop];
    return;
  }
  if (_capturedNativePopGesture != gesture) {
    [self restoreNativeInteractivePop];
    _capturedNativePopGesture = gesture;
    _nativePopWasEnabled = @(gesture.enabled);
  }
  gesture.enabled = NO;
}

- (void)restoreNativeInteractivePop {
  UIGestureRecognizer *gesture = _capturedNativePopGesture;
  if (gesture != nil && _nativePopWasEnabled != nil) {
    gesture.enabled = _nativePopWasEnabled.boolValue;
  }
  _capturedNativePopGesture = nil;
  _nativePopWasEnabled = nil;
}

- (void)installNavigationButtonIfNeeded {
  UIViewController *host = _host;
  UINavigationController *navigation = host.navigationController;
  if (_installedBackButton || navigation == nil ||
      navigation.viewControllers.firstObject == host) {
    return;
  }

  UINavigationItem *item = host.navigationItem;
  _savedLeftBarButtonItems = item.leftBarButtonItems;
  _savedHidesBackButton = @(item.hidesBackButton);
  UIBarButtonItem *button = [[UIBarButtonItem alloc]
      initWithImage:[UIImage systemImageNamed:@"chevron.backward"]
              style:UIBarButtonItemStylePlain
             target:self
             action:@selector(handleNavigationButton)];
  button.accessibilityLabel = NSLocalizedString(@"Back", @"Native back button");
  item.hidesBackButton = YES;
  item.leftBarButtonItems = @[ button ];
  _installedBackButton = YES;
}

- (void)restoreNavigationButton {
  UIViewController *host = _host;
  if (!_installedBackButton || host == nil) {
    return;
  }
  host.navigationItem.leftBarButtonItems = _savedLeftBarButtonItems;
  host.navigationItem.hidesBackButton = _savedHidesBackButton.boolValue;
  _savedLeftBarButtonItems = nil;
  _savedHidesBackButton = nil;
  _installedBackButton = NO;
}

- (void)handleNavigationButton {
  if (!_enabled) {
    return;
  }
  [self emitPhase:@"start"
         progress:0
           source:@"button"
            touch:CGPointZero
             edge:@"none"];
  [self emitPhase:@"commit"
         progress:1
           source:@"button"
            touch:CGPointZero
             edge:@"none"];
}

- (void)handleEdgeGesture:(UIScreenEdgePanGestureRecognizer *)gesture {
  UIView *view = gesture.view;
  if (view == nil) {
    return;
  }
  CGFloat multiplier = (gesture.edges & UIRectEdgeRight) != 0 ? -1 : 1;
  CGFloat width = MAX(view.bounds.size.width, 1);
  CGFloat translation = [gesture translationInView:view].x * multiplier;
  CGFloat progress = MIN(MAX(translation / width, 0), 1);
  _lastTouch = [gesture locationInView:view];

  switch (gesture.state) {
    case UIGestureRecognizerStateBegan:
      _gestureStarted = YES;
      _lastProgress = progress;
      [self emitPhase:@"start"
             progress:progress
               source:@"gesture"
                touch:_lastTouch
                 edge:nil];
      break;
    case UIGestureRecognizerStateChanged:
      if (!_gestureStarted) {
        return;
      }
      _lastProgress = progress;
      [self emitPhase:@"progress"
             progress:progress
               source:@"gesture"
                touch:_lastTouch
                 edge:nil];
      break;
    case UIGestureRecognizerStateEnded: {
      if (!_gestureStarted) {
        return;
      }
      _lastProgress = progress;
      CGFloat velocity = [gesture velocityInView:view].x * multiplier;
      BOOL shouldCommit = velocity > 600 || (velocity >= 0 && progress >= 0.35);
      [self emitPhase:shouldCommit ? @"commit" : @"cancel"
             progress:shouldCommit ? 1 : progress
               source:@"gesture"
                touch:_lastTouch
                 edge:nil];
      [self resetGesture];
      break;
    }
    case UIGestureRecognizerStateCancelled:
    case UIGestureRecognizerStateFailed:
      if (!_gestureStarted) {
        return;
      }
      [self emitPhase:@"cancel"
             progress:_lastProgress
               source:@"gesture"
                touch:_lastTouch
                 edge:nil];
      [self resetGesture];
      break;
    default:
      break;
  }
}

- (void)resetGesture {
  _gestureStarted = NO;
  _lastProgress = 0;
  _lastTouch = CGPointZero;
}

- (void)emitPhase:(NSString *)phase
         progress:(CGFloat)progress
           source:(NSString *)source
            touch:(CGPoint)touch
             edge:(nullable NSString *)edge {
  NSString *resolvedEdge = edge;
  if (resolvedEdge == nil) {
    resolvedEdge = (_edgeGesture.edges & UIRectEdgeRight) != 0
                       ? @"right"
                       : @"left";
  }
  NSDictionary<NSString *, id> *payload = @{
    @"platform" : @"ios",
    @"phase" : phase,
    @"progress" : @(MIN(MAX(progress, 0), 1)),
    @"source" : source,
    @"edge" : resolvedEdge,
    @"touchX" : @(touch.x),
    @"touchY" : @(touch.y),
  };
  [[_lynxContext getLynxView] sendGlobalEvent:LynxBackEventName
                                   withParams:@[ payload ]];
}

@end
