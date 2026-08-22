#import "ShareModule.h"

#import <Lynx/LynxContext.h>
#import <UIKit/UIKit.h>

static NSString *const kOutcomeSent = @"sent";
static NSString *const kOutcomeDismissed = @"dismissed";
static NSString *const kOutcomeBusy = @"busy";

// The @LynxNativeModule annotation is what cocoapods-lynx-library scans for;
// it expands to a harmless ObjC forward declaration when compiled.
//
// System share sheet exported to Lynx as `Share`. UIActivityViewController
// is the only platform sheet that reports a real completion, so iOS maps
// `completed` onto `sent` / `dismissed` verbatim and forwards the
// UIActivityType of the chosen target.
@LynxNativeModule("Share")
@implementation ShareModule {
  LynxContext *_context;
  LynxCallbackBlock _callback;
  UIActivityViewController *_activityController;
}

+ (NSString *)name {
  return @"Share";
}

+ (NSDictionary<NSString *, NSString *> *)methodLookup {
  return @{
    @"share" : NSStringFromSelector(@selector(share:callback:)),
  };
}

- (instancetype)initWithLynxContext:(LynxContext *)context {
  self = [super init];
  if (self) {
    _context = context;
  }
  return self;
}

- (void)share:(NSDictionary *)options callback:(LynxCallbackBlock)callback {
  dispatch_async(dispatch_get_main_queue(), ^{
    if (self->_callback != nil) {
      callback([self outcomeJSONWithCode:kOutcomeBusy
                            activityType:nil
                                 message:@"Another share request is already active"]);
      return;
    }
    NSError *error = nil;
    NSArray *items = [self activityItemsFromOptions:options error:&error];
    if (items == nil) {
      callback([self errorJSON:error.localizedDescription ?: @"Invalid share options"]);
      return;
    }
    UIViewController *presenter = [self presentingViewController];
    if (presenter == nil) {
      callback([self errorJSON:@"Share requires a view controller to present the sheet"]);
      return;
    }
    NSString *title = [self optionalString:options[@"title"]];
    self->_callback = [callback copy];
    UIActivityViewController *controller =
        [[UIActivityViewController alloc] initWithActivityItems:items
                                          applicationActivities:nil];
    if (title != nil) {
      // Mail-like targets read their subject line from this KVC key.
      [controller setValue:title forKey:@"subject"];
    }
    __weak ShareModule *weakSelf = self;
    controller.completionWithItemsHandler =
        ^(UIActivityType activityType, BOOL completed, NSArray *returnedItems,
          NSError *activityError) {
      dispatch_async(dispatch_get_main_queue(), ^{
        ShareModule *strongSelf = weakSelf;
        if (strongSelf == nil) {
          return;
        }
        strongSelf->_activityController = nil;
        if (activityError != nil) {
          [strongSelf finishWithJSON:
              [strongSelf errorJSON:activityError.localizedDescription
                                          ?: @"The share sheet failed"]];
        } else if (completed) {
          [strongSelf finishWithJSON:
              [strongSelf outcomeJSONWithCode:kOutcomeSent
                                 activityType:activityType
                                      message:@""]];
        } else {
          [strongSelf finishWithJSON:
              [strongSelf outcomeJSONWithCode:kOutcomeDismissed
                                 activityType:nil
                                      message:@"Share sheet was dismissed without a target"]];
        }
      });
    };
    // UIActivityViewController is a popover on iPad; without an anchor it
    // crashes at presentation time.
    UIPopoverPresentationController *popover = controller.popoverPresentationController;
    UIView *lynxView = self->_context.getLynxView;
    if (popover != nil && lynxView != nil) {
      popover.sourceView = lynxView;
      popover.sourceRect =
          CGRectMake(CGRectGetMidX(lynxView.bounds), CGRectGetMidY(lynxView.bounds), 0, 0);
      popover.permittedArrowDirections = 0;
      popover.canOverlapSourceViewRect = YES;
    }
    self->_activityController = controller;
    [presenter presentViewController:controller animated:YES completion:nil];
  });
}

- (void)destroy {
  dispatch_async(dispatch_get_main_queue(), ^{
    self->_callback = nil;
    [self->_activityController dismissViewControllerAnimated:NO completion:nil];
    self->_activityController = nil;
  });
}

#pragma mark - Activity items

/// Builds the activity item list, or nil with an error describing the first
/// invalid entry. Files must be existing file:// URLs — album picks and
/// Screenshot/FileSystem products already satisfy that on iOS.
- (nullable NSArray *)activityItemsFromOptions:(NSDictionary *)options
                                         error:(NSError **)error {
  NSMutableArray *items = [NSMutableArray array];
  NSString *text = [self optionalString:options[@"text"]];
  if (text != nil) {
    [items addObject:text];
  }
  NSString *url = [self optionalString:options[@"url"]];
  if (url != nil) {
    NSURL *link = [NSURL URLWithString:url];
    if (link == nil || link.scheme == nil) {
      *error = [self errorWithMessage:@"Share url must declare a scheme"];
      return nil;
    }
    if ([link.scheme.lowercaseString isEqualToString:@"javascript"] ||
        [link.scheme.lowercaseString isEqualToString:@"data"]) {
      *error = [self errorWithMessage:@"Share url scheme is not allowed"];
      return nil;
    }
    [items addObject:link];
  }
  id files = options[@"files"];
  if ([files isKindOfClass:NSArray.class]) {
    for (id entry in (NSArray *)files) {
      if (![entry isKindOfClass:NSString.class]) {
        continue;
      }
      NSString *uri = [(NSString *)entry
          stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
      if (uri.length == 0) {
        continue;
      }
      NSURL *fileURL = [NSURL URLWithString:uri];
      if (fileURL == nil || !fileURL.fileURL) {
        *error = [self errorWithMessage:
            [NSString stringWithFormat:@"Share reads file:// URIs on iOS: %@", uri]];
        return nil;
      }
      if (![NSFileManager.defaultManager fileExistsAtPath:fileURL.path]) {
        *error = [self errorWithMessage:
            [NSString stringWithFormat:@"Share file does not exist: %@", uri]];
        return nil;
      }
      [items addObject:fileURL];
    }
  }
  if (items.count == 0) {
    *error = [self errorWithMessage:@"Share requires a non-empty text, url or files payload"];
    return nil;
  }
  return items;
}

- (nullable NSString *)optionalString:(id)value {
  if (![value isKindOfClass:NSString.class]) {
    return nil;
  }
  NSString *trimmed = [(NSString *)value
      stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  return trimmed.length == 0 ? nil : trimmed;
}

- (NSError *)errorWithMessage:(NSString *)message {
  return [NSError errorWithDomain:@"LynxShareModule"
                             code:0
                         userInfo:@{NSLocalizedDescriptionKey : message}];
}

#pragma mark - Presentation

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

#pragma mark - Results

- (void)finishWithJSON:(NSString *)json {
  LynxCallbackBlock callback = _callback;
  _callback = nil;
  if (callback != nil) {
    callback(json);
  }
}

- (NSString *)outcomeJSONWithCode:(NSString *)code
                     activityType:(nullable NSString *)activityType
                          message:(NSString *)message {
  NSDictionary *value = @{
    @"code" : code,
    @"activityType" : activityType ?: NSNull.null,
    @"message" : message ?: @"",
  };
  return [self resultJSONWithValue:value error:@""];
}

- (NSString *)errorJSON:(NSString *)message {
  return [self resultJSONWithValue:nil error:message ?: @"Share failed"];
}

- (NSString *)resultJSONWithValue:(nullable NSDictionary *)value error:(NSString *)error {
  NSMutableDictionary *result = [NSMutableDictionary dictionary];
  result[@"error"] = error;
  if (value != nil) {
    result[@"value"] = value;
  }
  NSData *data = [NSJSONSerialization dataWithJSONObject:result options:0 error:nil];
  if (data == nil) {
    return @"{\"error\":\"Unable to encode share result\"}";
  }
  return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

@end
