#import "ScreenshotModule.h"

#import <Lynx/LynxContext.h>
#import <Lynx/LynxView.h>
#import <UIKit/UIKit.h>

static const NSInteger kDefaultJPEGQuality = 80;
static const NSUInteger kMaxIDSelectorLength = 128;
static const NSUInteger kMaxFileNameLength = 120;

/** Validated request shared by both entry points. */
@interface LynxScreenshotRequest : NSObject
@property (nonatomic, copy, nullable) NSString *idSelector;
@property (nonatomic, assign) BOOL jpeg;
@property (nonatomic, assign) int quality;
@property (nonatomic, copy, nullable) NSString *fileName;
@end

@implementation LynxScreenshotRequest
@end

// The @LynxNativeModule annotation is what cocoapods-lynx-library scans for;
// it expands to a harmless ObjC forward declaration when compiled.
// View snapshots encoded into the app cache directory, exported to Lynx as
// `Screenshot`. `capture` renders the LynxView (or the element matching an
// idSelector); `capturePage` snapshots the whole key window, so it also
// contains native chrome outside the LynxView.
@LynxNativeModule("Screenshot")
@implementation ScreenshotModule {
  __weak LynxContext *_lynxContext;
}

- (instancetype)initWithLynxContext:(LynxContext *)context {
  self = [super init];
  if (self) {
    _lynxContext = context;
  }
  return self;
}

+ (NSString *)name {
  return @"Screenshot";
}

+ (NSDictionary<NSString *, NSString *> *)methodLookup {
  return @{
    @"capture" : NSStringFromSelector(@selector(capture:callback:)),
    @"capturePage" : NSStringFromSelector(@selector(capturePage:callback:)),
  };
}

#pragma mark - Capture

- (void)capture:(NSDictionary *)options callback:(LynxCallbackBlock)callback {
  NSError *requestError = nil;
  LynxScreenshotRequest *request = [self requestFromOptions:options error:&requestError];
  if (request == nil) {
    callback([self errorJSON:requestError.localizedDescription]);
    return;
  }
  dispatch_async(dispatch_get_main_queue(), ^{
    LynxView *lynxView = [self->_lynxContext getLynxView];
    if (lynxView == nil) {
      callback([self errorJSON:@"LynxView is not attached yet"]);
      return;
    }
    UIView *target = lynxView;
    if (request.idSelector.length > 0) {
      target = [lynxView viewWithIdSelector:request.idSelector];
    }
    if (target == nil) {
      callback([self errorJSON:[NSString
          stringWithFormat:@"No view matches idSelector: %@", request.idSelector]]);
      return;
    }
    [self saveSnapshotOfView:target request:request callback:callback];
  });
}

- (void)capturePage:(NSDictionary *)options callback:(LynxCallbackBlock)callback {
  NSError *requestError = nil;
  LynxScreenshotRequest *request = [self requestFromOptions:options error:&requestError];
  if (request == nil) {
    callback([self errorJSON:requestError.localizedDescription]);
    return;
  }
  dispatch_async(dispatch_get_main_queue(), ^{
    UIWindow *window = [self keyWindow];
    if (window == nil) {
      callback([self errorJSON:@"Screenshot has no visible window"]);
      return;
    }
    [self saveSnapshotOfView:window request:request callback:callback];
  });
}

#pragma mark - Snapshot pipeline

- (void)saveSnapshotOfView:(UIView *)view
                   request:(LynxScreenshotRequest *)request
                  callback:(LynxCallbackBlock)callback {
  if (view.bounds.size.width <= 0 || view.bounds.size.height <= 0) {
    callback([self errorJSON:@"Screenshot target has not been laid out yet"]);
    return;
  }
  UIImage *image = [self snapshotView:view jpeg:request.jpeg];
  if (image == nil) {
    callback([self errorJSON:@"Unable to render the screenshot target"]);
    return;
  }
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    NSError *writeError = nil;
    NSURL *uri = [self writeImage:image request:request error:&writeError];
    if (uri == nil) {
      callback([self errorJSON:writeError.localizedDescription
                               ?: @"Unable to write the screenshot"]);
      return;
    }
    callback([self resultJSONWithURI:uri.absoluteString
                               width:image.size.width * image.scale
                              height:image.size.height * image.scale]);
  });
}

- (nullable UIImage *)snapshotView:(UIView *)view jpeg:(BOOL)jpeg {
  UIGraphicsImageRenderer *renderer =
      [[UIGraphicsImageRenderer alloc] initWithSize:view.bounds.size];
  return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
    if (jpeg) {
      // JPEG has no alpha channel; transparent pixels would turn black.
      [[UIColor whiteColor] setFill];
      UIRectFill(view.bounds);
    }
    // afterScreenUpdates:NO keeps the current pixels; the layer fallback
    // covers views that are not composited on screen yet.
    BOOL drew = [view drawViewHierarchyInRect:view.bounds afterScreenUpdates:NO];
    if (!drew) {
      [view.layer renderInContext:context.CGContext];
    }
  }];
}

- (nullable NSURL *)writeImage:(UIImage *)image
                       request:(LynxScreenshotRequest *)request
                         error:(NSError **)error {
  NSData *data = request.jpeg
      ? UIImageJPEGRepresentation(image, request.quality / 100.0)
      : UIImagePNGRepresentation(image);
  if (data == nil) {
    [self assignError:error message:@"Unable to encode the screenshot"];
    return nil;
  }
  NSURL *directory = [[NSFileManager defaultManager]
      URLForDirectory:NSCachesDirectory
             inDomain:NSUserDomainMask
    appropriateForURL:nil
               create:YES
                error:error];
  if (directory == nil) {
    return nil;
  }
  directory = [directory URLByAppendingPathComponent:@"LynxImages" isDirectory:YES];
  if (![[NSFileManager defaultManager] createDirectoryAtURL:directory
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:error]) {
    return nil;
  }
  NSString *name = request.fileName.length > 0 ? request.fileName : @"screenshot";
  NSURL *destination = [directory URLByAppendingPathComponent:
      [NSString stringWithFormat:@"%@-%@%@",
          NSUUID.UUID.UUIDString,
          name,
          request.jpeg ? @".jpg" : @".png"]];
  if (![data writeToURL:destination options:NSDataWritingAtomic error:error]) {
    return nil;
  }
  return destination;
}

#pragma mark - Options and results

- (nullable LynxScreenshotRequest *)requestFromOptions:(NSDictionary *)options
                                                 error:(NSError **)error {
  NSString *idSelector = [self optionalString:options key:@"idSelector"];
  if (idSelector.length > kMaxIDSelectorLength) {
    [self assignError:error
               message:@"Screenshot idSelector is longer than 128 characters"];
    return nil;
  }

  NSString *format = [self optionalString:options key:@"format"];
  BOOL jpeg = NO;
  if (format == nil || [format isEqualToString:@"png"]) {
    jpeg = NO;
  } else if ([format isEqualToString:@"jpeg"]) {
    jpeg = YES;
  } else {
    [self assignError:error message:[@"Invalid screenshot format: "
        stringByAppendingString:format ?: @""]];
    return nil;
  }

  NSNumber *qualityNumber = options[@"quality"];
  NSInteger quality = kDefaultJPEGQuality;
  if (qualityNumber != nil && ![qualityNumber isKindOfClass:NSNull.class]) {
    if (![qualityNumber isKindOfClass:NSNumber.class]) {
      [self assignError:error message:@"Screenshot quality must be a number"];
      return nil;
    }
    quality = qualityNumber.integerValue;
    if (quality < 1 || quality > 100) {
      [self assignError:error message:@"Screenshot quality must be between 1 and 100"];
      return nil;
    }
  }

  LynxScreenshotRequest *request = [[LynxScreenshotRequest alloc] init];
  request.idSelector = idSelector;
  request.jpeg = jpeg;
  request.quality = (int)quality;
  request.fileName = [self sanitizeName:[self optionalString:options key:@"fileName"]];
  return request;
}

- (nullable NSString *)optionalString:(NSDictionary *)options key:(NSString *)key {
  NSString *value = options[key];
  if (![value isKindOfClass:NSString.class]) {
    return nil;
  }
  NSString *trimmed = [value stringByTrimmingCharactersInSet:
      [NSCharacterSet whitespaceAndNewlineCharacterSet]];
  return trimmed.length == 0 ? nil : trimmed;
}

- (nullable NSString *)sanitizeName:(nullable NSString *)name {
  if (name == nil) {
    return nil;
  }
  NSCharacterSet *invalid = [NSCharacterSet characterSetWithCharactersInString:
      @"\\/:*?\"<>|"];
  NSMutableArray *characters = [NSMutableArray arrayWithCapacity:name.length];
  for (NSUInteger index = 0; index < name.length; index++) {
    unichar character = [name characterAtIndex:index];
    if (character < 0x20 || [invalid characterIsMember:character]) {
      [characters addObject:@"_"];
    } else {
      [characters addObject:[NSString stringWithFormat:@"%C", character]];
    }
  }
  NSString *sanitized = [characters componentsJoinedByString:@""];
  sanitized = [sanitized stringByTrimmingCharactersInSet:
      [NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if (sanitized.length == 0) {
    return nil;
  }
  if (sanitized.length > kMaxFileNameLength) {
    sanitized = [sanitized substringFromIndex:sanitized.length - kMaxFileNameLength];
  }
  return sanitized;
}

- (nullable UIWindow *)keyWindow {
  for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
    if (![scene isKindOfClass:UIWindowScene.class] ||
        scene.activationState != UISceneActivationStateForegroundActive) {
      continue;
    }
    for (UIWindow *window in ((UIWindowScene *)scene).windows) {
      if (window.isKeyWindow) {
        return window;
      }
    }
  }
  return nil;
}

- (void)assignError:(NSError **)error message:(NSString *)message {
  if (error != NULL) {
    *error = [NSError errorWithDomain:@"LynxScreenshot"
                                 code:1
                             userInfo:@{ NSLocalizedDescriptionKey : message }];
  }
}

- (NSString *)resultJSONWithURI:(NSString *)uri width:(CGFloat)width height:(CGFloat)height {
  NSDictionary *value = @{
    @"uri" : uri,
    @"width" : @(round(width)),
    @"height" : @(round(height)),
  };
  return [self jsonWithDictionary:@{ @"value" : value, @"error" : @"" }];
}

- (NSString *)errorJSON:(NSString *)message {
  return [self jsonWithDictionary:@{ @"value" : NSNull.null, @"error" : message }];
}

- (NSString *)jsonWithDictionary:(NSDictionary *)dictionary {
  NSData *data = [NSJSONSerialization dataWithJSONObject:dictionary options:0 error:nil];
  if (data == nil) {
    return @"{\"value\":null,\"error\":\"Unable to encode Screenshot result\"}";
  }
  return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

@end
