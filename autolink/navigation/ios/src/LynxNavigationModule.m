#import "LynxNavigationModule.h"
#import "LynxPredictiveBackOverlay.h"

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
// Route navigation and Back interception exported to Lynx as `Navigation`.
@LynxNativeModule("Navigation")
@implementation LynxNavigationModule {
  LynxContext *_context;
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
  BOOL _gestureFinishing;
  BOOL _destroyed;
  NSInteger _configurationRevision;
  NSString *_configuredInterceptorID;
  NSString *_configuredTargetID;
  NSUInteger _nextGestureID;
  NSUInteger _gestureID;
  NSString *_gestureInterceptorID;
  id<LynxPredictiveBackAnimationTarget> _gestureTarget;
  CGFloat _lastProgress;
  CGPoint _lastTouch;
}

static id<LynxRouteHandler> _Nullable _routeHandler = nil;

+ (NSString *)name {
  return @"Navigation";
}

+ (NSDictionary<NSString *, NSString *> *)methodLookup {
  return @{
    @"open" : NSStringFromSelector(@selector(open:callback:)),
    @"close" : NSStringFromSelector(@selector(close:)),
    @"openURL" : NSStringFromSelector(@selector(openURL:callback:)),
    @"setEnabled" : NSStringFromSelector(@selector(setEnabled:callback:)),
    @"configure" : NSStringFromSelector(@selector(
        configure:interceptorId:targetId:revision:callback:)),
  };
}

+ (void)setRouteHandler:(nullable id<LynxRouteHandler>)handler {
  _routeHandler = handler;
}

- (instancetype)initWithLynxContext:(LynxContext *)context {
  self = [super init];
  if (self) {
    _context = context;
    _edgeGesture = [[UIScreenEdgePanGestureRecognizer alloc]
        initWithTarget:self
                action:@selector(handleEdgeGesture:)];
    _edgeGesture.cancelsTouchesInView = YES;
    _edgeGesture.delaysTouchesBegan = NO;
    _edgeGesture.delaysTouchesEnded = NO;
    _edgeGesture.delegate = self;
    _edgeGesture.enabled = NO;
    _configuredInterceptorID = @"";
    _configuredTargetID = @"";
    _gestureInterceptorID = @"";
  }
  return self;
}

#pragma mark - Route navigation

- (void)open:(NSDictionary *)options callback:(LynxCallbackBlock)callback {
  id<LynxRouteHandler> handler = _routeHandler;
  UIViewController *host = [self presentingViewController];
  if (handler == nil || host == nil) {
    callback(@"Navigation has no visible UIViewController host");
    return;
  }
  [handler openFromViewController:host options:options success:callback];
}

- (void)close:(LynxCallbackBlock)callback {
  id<LynxRouteHandler> handler = _routeHandler;
  UIViewController *host = [self presentingViewController];
  if (handler == nil || host == nil) {
    callback(@"Navigation has no visible UIViewController host");
    return;
  }
  [handler closeFromViewController:host success:callback];
}

- (void)openURL:(NSString *)url callback:(LynxCallbackBlock)callback {
  dispatch_async(dispatch_get_main_queue(), ^{
    NSURL *target = [NSURL URLWithString:url];
    if (url == nil || url.length == 0 || target == nil || target.scheme.length == 0) {
      callback(@"Invalid URL");
      return;
    }
    [UIApplication.sharedApplication openURL:target
                                     options:@{}
                           completionHandler:^(BOOL success) {
      callback(success ? @"" : @"Unable to open URL");
    }];
  });
}

- (nullable UIViewController *)presentingViewController {
  UIViewController *root = _context.getLynxView.window.rootViewController;
  if (root == nil) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
      if (![scene isKindOfClass:UIWindowScene.class]) {
        continue;
      }
      for (UIWindow *window in ((UIWindowScene *)scene).windows) {
        if (window.isKeyWindow) {
          root = window.rootViewController;
          break;
        }
      }
      if (root != nil) {
        break;
      }
    }
  }
  return [self topViewController:root];
}

- (nullable UIViewController *)topViewController:(nullable UIViewController *)controller {
  if (controller.presentedViewController != nil) {
    return [self topViewController:controller.presentedViewController];
  }
  if ([controller isKindOfClass:UINavigationController.class]) {
    return [self topViewController:((UINavigationController *)controller).visibleViewController];
  }
  if ([controller isKindOfClass:UITabBarController.class]) {
    return [self topViewController:((UITabBarController *)controller).selectedViewController];
  }
  return controller;
}

#pragma mark - Back interception

- (void)setEnabled:(BOOL)enabled callback:(LynxCallbackBlock)callback {
  dispatch_async(dispatch_get_main_queue(), ^{
    if (self->_destroyed) {
      callback(@"Navigation has already been destroyed");
      return;
    }
    if (enabled && ![self attachToCurrentHost]) {
      callback(@"Navigation has no UIViewController host");
      return;
    }
    self->_configurationRevision += 1;
    self->_configuredInterceptorID = @"";
    self->_configuredTargetID = @"";
    if (!enabled) {
      [self cancelActiveGestureEmittingEvent:YES];
    }
    self->_enabled = enabled;
    [self updateInterception];
    callback(@"");
  });
}

- (void)configure:(BOOL)enabled
    interceptorId:(NSString *)interceptorID
         targetId:(NSString *)targetID
         revision:(NSInteger)revision
         callback:(LynxCallbackBlock)callback {
  dispatch_async(dispatch_get_main_queue(), ^{
    if (self->_destroyed) {
      callback(@"Navigation has already been destroyed");
      return;
    }
    if (revision < self->_configurationRevision) {
      callback(@"");
      return;
    }
    if (enabled && ![self attachToCurrentHost]) {
      callback(@"Navigation has no UIViewController host");
      return;
    }
    self->_configurationRevision = MAX(revision, 0);
    self->_enabled = enabled;
    self->_configuredInterceptorID = [interceptorID copy] ?: @"";
    self->_configuredTargetID = [targetID copy] ?: @"";
    // The in-flight gesture owns the snapshot it captured at begin. Merely
    // stage this configuration for the following gesture.
    if (!self->_gestureStarted && !self->_gestureFinishing) {
      [self updateInterception];
    }
    callback(@"");
  });
}

- (void)destroy {
  dispatch_async(dispatch_get_main_queue(), ^{
    if (self->_destroyed) {
      return;
    }
    self->_destroyed = YES;
    [self cancelActiveGestureEmittingEvent:NO];
    self->_enabled = NO;
    self->_visible = NO;
    [self resetGesture];
    [self updateInterception];
    [self detachFromHost];
    self->_context = nil;
  });
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
  UIViewController *host = _host;
  UINavigationController *navigation = host.navigationController;
  return gestureRecognizer == _edgeGesture && _enabled && _visible &&
         host != nil && host.viewIfLoaded.window != nil &&
         (navigation == nil || navigation.topViewController == host) &&
         host.transitionCoordinator == nil;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
    shouldRecognizeSimultaneouslyWithGestureRecognizer:
        (UIGestureRecognizer *)otherGestureRecognizer {
  // Lynx pages commonly contain a vertical UIScrollView. Let it resolve its
  // own pan without starving the leading-edge Back recognizer.
  return gestureRecognizer == _edgeGesture ||
         otherGestureRecognizer == _edgeGesture;
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
  // UINavigationController installs interactivePopGestureRecognizer on its
  // own view. Keep the overlay recognizer at that same hierarchy level so the
  // parent pop recognizer cannot win the edge touch before predictive Back.
  UIView *gestureHost = host.navigationController.view ?: host.view;
  [gestureHost addGestureRecognizer:_edgeGesture];
  UIGestureRecognizer *nativePopGesture =
      host.navigationController.interactivePopGestureRecognizer;
  if (nativePopGesture != nil && nativePopGesture.view == gestureHost) {
    [nativePopGesture requireGestureRecognizerToFail:_edgeGesture];
  }

  LynxBackLifecycleObserver *observer = [[LynxBackLifecycleObserver alloc] init];
  __weak LynxNavigationModule *weakSelf = self;
  observer.visibilityDidChange = ^(BOOL visible) {
    LynxNavigationModule *strongSelf = weakSelf;
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
  UIResponder *responder = [_context getLynxView];
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
  if (shouldIntercept) {
    [self suspendNativeInteractivePopIfNeeded];
    _edgeGesture.enabled = YES;
    [self installNavigationButtonIfNeeded];
  } else {
    _edgeGesture.enabled = NO;
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
  if (_installedBackButton || navigation == nil || navigation.navigationBarHidden ||
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
  _lastProgress = 0;
  _lastTouch = CGPointZero;
  [self beginGestureWithSource:@"button" edge:@"none"];
  [self commitActiveGestureWithSource:@"button" edge:@"none"];
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
      _lastProgress = progress;
      [self beginGestureWithSource:@"gesture" edge:nil];
      break;
    case UIGestureRecognizerStateChanged: {
      if (!_gestureStarted || _gestureFinishing) {
        return;
      }
      _lastProgress = progress;
      NSString *edge = [self resolvedEdge:nil];
      if (_gestureTarget != nil) {
        [_gestureTarget updateBackProgress:progress edge:edge];
      } else {
        [self emitPhase:@"progress"
               progress:progress
                 source:@"gesture"
                  touch:_lastTouch
                   edge:edge];
      }
      break;
    }
    case UIGestureRecognizerStateEnded: {
      if (!_gestureStarted || _gestureFinishing) {
        return;
      }
      _lastProgress = progress;
      CGFloat velocity = [gesture velocityInView:view].x * multiplier;
      BOOL shouldCommit = velocity > 600 || (velocity >= 0 && progress >= 0.35);
      if (shouldCommit) {
        [self commitActiveGestureWithSource:@"gesture" edge:nil];
      } else {
        [self cancelActiveGestureEmittingEvent:YES];
      }
      break;
    }
    case UIGestureRecognizerStateCancelled:
    case UIGestureRecognizerStateFailed:
      if (!_gestureStarted) {
        return;
      }
      [self cancelActiveGestureEmittingEvent:YES];
      break;
    default:
      break;
  }
}

- (void)beginGestureWithSource:(NSString *)source
                          edge:(nullable NSString *)edge {
  if (_gestureStarted || _gestureFinishing) {
    return;
  }
  _gestureStarted = YES;
  _gestureFinishing = NO;
  _gestureID = ++_nextGestureID;
  _gestureInterceptorID = [_configuredInterceptorID copy] ?: @"";
  _gestureTarget = LynxPredictiveBackTargetForContext(
      _context, _configuredTargetID ?: @"");
  NSString *resolvedEdge = [self resolvedEdge:edge];
  if (_gestureTarget != nil) {
    [_gestureTarget beginBackFromEdge:resolvedEdge];
    [_gestureTarget updateBackProgress:_lastProgress edge:resolvedEdge];
  }
  [self emitPhase:@"start"
         progress:_lastProgress
           source:source
            touch:_lastTouch
             edge:resolvedEdge];
}

- (void)commitActiveGestureWithSource:(NSString *)source
                                  edge:(nullable NSString *)edge {
  if (!_gestureStarted || _gestureFinishing) {
    return;
  }
  NSString *resolvedEdge = [self resolvedEdge:edge];
  id<LynxPredictiveBackAnimationTarget> target = _gestureTarget;
  if (target == nil) {
    [self emitPhase:@"commit"
           progress:1
             source:source
              touch:_lastTouch
               edge:resolvedEdge];
    [self resetGesture];
    [self updateInterception];
    return;
  }

  _gestureFinishing = YES;
  NSUInteger finishingGestureID = _gestureID;
  __weak LynxNavigationModule *weakSelf = self;
  [target commitBackWithCompletion:^{
    LynxNavigationModule *strongSelf = weakSelf;
    if (strongSelf == nil || strongSelf->_destroyed ||
        !strongSelf->_gestureStarted ||
        strongSelf->_gestureID != finishingGestureID) {
      return;
    }
    [strongSelf emitPhase:@"commit"
                 progress:1
                   source:source
                    touch:strongSelf->_lastTouch
                     edge:resolvedEdge];
    [strongSelf resetGesture];
    [strongSelf updateInterception];
  }];
}

- (void)cancelActiveGestureEmittingEvent:(BOOL)emitEvent {
  if (!_gestureStarted) {
    return;
  }
  [_gestureTarget cancelBack];
  if (emitEvent) {
    [self emitPhase:@"cancel"
           progress:_lastProgress
             source:@"gesture"
              touch:_lastTouch
               edge:nil];
  }
  [self resetGesture];
  if (!_destroyed) {
    [self updateInterception];
  }
}

- (void)resetGesture {
  _gestureStarted = NO;
  _gestureFinishing = NO;
  _gestureTarget = nil;
  _gestureInterceptorID = @"";
  _gestureID = 0;
  _lastProgress = 0;
  _lastTouch = CGPointZero;
}

- (NSString *)resolvedEdge:(nullable NSString *)edge {
  if (edge != nil) {
    return edge;
  }
  return (_edgeGesture.edges & UIRectEdgeRight) != 0 ? @"right" : @"left";
}

- (void)emitPhase:(NSString *)phase
         progress:(CGFloat)progress
           source:(NSString *)source
            touch:(CGPoint)touch
             edge:(nullable NSString *)edge {
  NSString *resolvedEdge = [self resolvedEdge:edge];
  NSDictionary<NSString *, id> *payload = @{
    @"platform" : @"ios",
    @"phase" : phase,
    @"progress" : @(MIN(MAX(progress, 0), 1)),
    @"source" : source,
    @"edge" : resolvedEdge,
    @"touchX" : @(touch.x),
    @"touchY" : @(touch.y),
    @"interceptorId" : _gestureInterceptorID ?: @"",
    @"gestureId" : @(_gestureID),
  };
  [[_context getLynxView] sendGlobalEvent:LynxBackEventName
                                   withParams:@[ payload ]];
}

@end
