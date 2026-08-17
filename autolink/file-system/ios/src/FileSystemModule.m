#import "FileSystemModule.h"

#import <Lynx/LynxContext.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static const NSUInteger kMaximumReadBytes = 20 * 1024 * 1024;

@interface FileSystemModule () <UIDocumentPickerDelegate>
@end

// Exported to Lynx as `FileSystem`.
@LynxNativeModule("FileSystem")
@implementation FileSystemModule {
  LynxContext *_context;
  LynxCallbackBlock _pickCallback;
  UIDocumentPickerViewController *_pickerController;
  NSInteger _maxSelection;
}

+ (NSString *)name {
  return @"FileSystem";
}

+ (NSDictionary<NSString *, NSString *> *)methodLookup {
  return @{
    @"pick" : NSStringFromSelector(@selector(pick:callback:)),
    @"stat" : NSStringFromSelector(@selector(stat:callback:)),
    @"copyToCache" : NSStringFromSelector(@selector(copyToCache:callback:)),
    @"readText" : NSStringFromSelector(@selector(readText:maxBytes:callback:)),
    @"readBase64" : NSStringFromSelector(@selector(readBase64:maxBytes:callback:)),
  };
}

- (instancetype)initWithLynxContext:(LynxContext *)context {
  self = [super init];
  if (self) {
    _context = context;
  }
  return self;
}

- (void)destroy {
  dispatch_async(dispatch_get_main_queue(), ^{
    self->_pickCallback = nil;
    [self->_pickerController dismissViewControllerAnimated:NO completion:nil];
    self->_pickerController = nil;
  });
}

#pragma mark - File picker

- (void)pick:(NSInteger)maxSelection callback:(LynxCallbackBlock)callback {
  dispatch_async(dispatch_get_main_queue(), ^{
    if (maxSelection < 1 || maxSelection > 50) {
      callback([self pickerResultJSONWithURIs:@[]
                                        error:@"File picker maxSelection must be between 1 and 50"]);
      return;
    }
    if (self->_pickCallback != nil) {
      callback([self pickerResultJSONWithURIs:@[]
                                        error:@"Another file picker request is already active"]);
      return;
    }
    self->_pickCallback = [callback copy];
    self->_maxSelection = maxSelection;
    [self presentDocumentPicker];
  });
}

- (void)presentDocumentPicker {
  UIDocumentPickerViewController *picker;
  if (@available(iOS 14.0, *)) {
    picker = [[UIDocumentPickerViewController alloc]
        initForOpeningContentTypes:@[ UTTypeItem ]
                            asCopy:YES];
  } else {
    picker = [[UIDocumentPickerViewController alloc]
        initWithDocumentTypes:@[ (__bridge NSString *)kUTTypeItem ]
                       inMode:UIDocumentPickerModeImport];
  }
  picker.delegate = self;
  picker.allowsMultipleSelection = _maxSelection > 1;

  UIViewController *presenter = [self presentingViewController];
  if (presenter == nil) {
    [self finishPickerWithError:@"Unable to find a view controller for the file picker"];
    return;
  }
  _pickerController = picker;
  [presenter presentViewController:picker animated:YES completion:nil];
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

#pragma mark - UIDocumentPickerDelegate

- (void)documentPicker:(UIDocumentPickerViewController *)controller
    didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
  [controller dismissViewControllerAnimated:YES completion:nil];
  _pickerController = nil;
  NSArray<NSURL *> *limited = urls.count > (NSUInteger)_maxSelection
      ? [urls subarrayWithRange:NSMakeRange(0, (NSUInteger)_maxSelection)]
      : urls;
  if (limited.count == 0) {
    [self finishPickerWithURIs:@[]];
    return;
  }

  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    NSMutableArray<NSString *> *uris = [NSMutableArray array];
    __block NSString *firstError = nil;
    for (NSURL *sourceURL in limited) {
      BOOL accessing = [sourceURL startAccessingSecurityScopedResource];
      __block NSURL *destination = nil;
      __block NSError *copyError = nil;
      NSFileCoordinator *coordinator =
          [[NSFileCoordinator alloc] initWithFilePresenter:nil];
      [coordinator coordinateReadingItemAtURL:sourceURL
                                      options:0
                                        error:&copyError
                                   byAccessor:^(NSURL *coordinatedURL) {
        destination = [self copyPickedURLToCache:coordinatedURL error:&copyError];
      }];
      if (accessing) {
        [sourceURL stopAccessingSecurityScopedResource];
      }
      if (destination != nil) {
        [uris addObject:destination.absoluteString];
      } else if (firstError == nil) {
        firstError = copyError.localizedDescription ?: @"Unable to copy a selected file";
      }
    }
    dispatch_async(dispatch_get_main_queue(), ^{
      if (uris.count == 0 && firstError.length > 0) {
        [self finishPickerWithError:firstError];
      } else {
        [self finishPickerWithURIs:uris];
      }
    });
  });
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
  [controller dismissViewControllerAnimated:YES completion:nil];
  _pickerController = nil;
  [self finishPickerWithURIs:@[]];
}

- (nullable NSURL *)copyPickedURLToCache:(NSURL *)sourceURL error:(NSError **)error {
  NSURL *base = [[NSFileManager defaultManager]
      URLForDirectory:NSCachesDirectory
             inDomain:NSUserDomainMask
    appropriateForURL:nil
               create:YES
                error:error];
  if (base == nil) {
    return nil;
  }
  NSURL *directory = [[base URLByAppendingPathComponent:@"LynxPicker"]
      URLByAppendingPathComponent:@"files"];
  if (![[NSFileManager defaultManager] createDirectoryAtURL:directory
                                withIntermediateDirectories:YES
                                                 attributes:nil
                                                      error:error]) {
    return nil;
  }
  NSString *name = sourceURL.lastPathComponent.length > 0
      ? sourceURL.lastPathComponent
      : @"file";
  NSURL *destination = [directory URLByAppendingPathComponent:
      [NSString stringWithFormat:@"%@-%@", NSUUID.UUID.UUIDString, name]];
  return [[NSFileManager defaultManager] copyItemAtURL:sourceURL
                                                toURL:destination
                                                error:error]
      ? destination
      : nil;
}

- (void)finishPickerWithURIs:(NSArray<NSString *> *)uris {
  [self finishPickerWithResult:[self pickerResultJSONWithURIs:uris error:@""]];
}

- (void)finishPickerWithError:(NSString *)error {
  [self finishPickerWithResult:[self pickerResultJSONWithURIs:@[] error:error]];
}

- (void)finishPickerWithResult:(NSString *)result {
  LynxCallbackBlock callback = _pickCallback;
  _pickCallback = nil;
  if (callback != nil) {
    callback(result);
  }
}

- (NSString *)pickerResultJSONWithURIs:(NSArray<NSString *> *)uris
                                 error:(NSString *)error {
  NSData *data = [NSJSONSerialization dataWithJSONObject:@{
    @"uris" : uris,
    @"error" : error,
  } options:0 error:nil];
  if (data == nil) {
    return @"{\"uris\":[],\"error\":\"Unable to encode file picker result\"}";
  }
  return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

#pragma mark - File operations

- (void)stat:(NSString *)uri callback:(LynxCallbackBlock)callback {
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    NSError *error = nil;
    NSURL *url = [self fileURL:uri error:&error];
    NSDictionary *info = url == nil ? nil : [self fileInfoForURL:url uri:uri error:&error];
    [self complete:callback value:info error:error];
  });
}

- (void)copyToCache:(NSString *)uri callback:(LynxCallbackBlock)callback {
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    NSError *error = nil;
    NSURL *source = [self fileURL:uri error:&error];
    NSURL *destination = source == nil ? nil : [self copyURLToCache:source error:&error];
    [self complete:callback value:destination.absoluteString error:error];
  });
}

- (void)readText:(NSString *)uri
        maxBytes:(NSInteger)maxBytes
         callback:(LynxCallbackBlock)callback {
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    NSError *error = nil;
    NSURL *url = [self fileURL:uri error:&error];
    NSData *data = url == nil ? nil : [self dataForURL:url maxBytes:maxBytes error:&error];
    NSString *value = nil;
    if (data != nil) {
      value = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
      if (value == nil) {
        error = [self errorWithMessage:@"File is not valid UTF-8"];
      }
    }
    [self complete:callback value:value error:error];
  });
}

- (void)readBase64:(NSString *)uri
          maxBytes:(NSInteger)maxBytes
           callback:(LynxCallbackBlock)callback {
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    NSError *error = nil;
    NSURL *url = [self fileURL:uri error:&error];
    NSData *data = url == nil ? nil : [self dataForURL:url maxBytes:maxBytes error:&error];
    NSString *value = [data base64EncodedStringWithOptions:0];
    [self complete:callback value:value error:error];
  });
}

- (nullable NSURL *)fileURL:(NSString *)uri error:(NSError **)error {
  NSURL *url = [NSURL URLWithString:[uri stringByTrimmingCharactersInSet:
      NSCharacterSet.whitespaceAndNewlineCharacterSet]];
  if (url == nil || !url.isFileURL) {
    if (error != NULL) {
      *error = [self errorWithMessage:@"FileSystem supports file:// URIs on iOS"];
    }
    return nil;
  }
  return url;
}

- (nullable NSDictionary *)fileInfoForURL:(NSURL *)url
                                      uri:(NSString *)uri
                                    error:(NSError **)error {
  BOOL accessing = [url startAccessingSecurityScopedResource];
  NSDictionary *values = [url resourceValuesForKeys:@[
    NSURLNameKey,
    NSURLFileSizeKey,
    NSURLIsRegularFileKey,
    NSURLTypeIdentifierKey,
  ] error:error];
  if (accessing) {
    [url stopAccessingSecurityScopedResource];
  }
  if (values == nil) {
    return nil;
  }
  if ([values[NSURLIsRegularFileKey] isEqual:@NO]) {
    if (error != NULL) {
      *error = [self errorWithMessage:@"URI does not reference a regular file"];
    }
    return nil;
  }

  NSString *name = values[NSURLNameKey];
  if (name.length == 0) {
    name = url.lastPathComponent.length > 0 ? url.lastPathComponent : @"file";
  }
  NSString *mimeType = [self mimeTypeForIdentifier:values[NSURLTypeIdentifierKey]];
  NSNumber *size = values[NSURLFileSizeKey];
  return @{
    @"uri" : uri,
    @"name" : name,
    @"mimeType" : mimeType ?: NSNull.null,
    @"size" : size ?: NSNull.null,
  };
}

- (nullable NSURL *)copyURLToCache:(NSURL *)source error:(NSError **)error {
  BOOL accessing = [source startAccessingSecurityScopedResource];
  NSURL *base = [[NSFileManager defaultManager]
      URLForDirectory:NSCachesDirectory
             inDomain:NSUserDomainMask
    appropriateForURL:nil
               create:YES
                error:error];
  if (base == nil) {
    if (accessing) [source stopAccessingSecurityScopedResource];
    return nil;
  }
  NSURL *directory = [base URLByAppendingPathComponent:@"LynxFiles" isDirectory:YES];
  if (![[NSFileManager defaultManager] createDirectoryAtURL:directory
                                withIntermediateDirectories:YES
                                                 attributes:nil
                                                      error:error]) {
    if (accessing) [source stopAccessingSecurityScopedResource];
    return nil;
  }

  NSString *name = source.lastPathComponent.length > 0
      ? source.lastPathComponent
      : @"file";
  NSURL *destination = [directory URLByAppendingPathComponent:
      [NSString stringWithFormat:@"%@-%@", NSUUID.UUID.UUIDString, name]];
  BOOL copied = [[NSFileManager defaultManager] copyItemAtURL:source
                                                        toURL:destination
                                                        error:error];
  if (accessing) {
    [source stopAccessingSecurityScopedResource];
  }
  return copied ? destination : nil;
}

- (nullable NSData *)dataForURL:(NSURL *)url
                       maxBytes:(NSInteger)maxBytes
                           error:(NSError **)error {
  if (maxBytes < 1 || maxBytes > (NSInteger)kMaximumReadBytes) {
    if (error != NULL) {
      *error = [self errorWithMessage:[NSString stringWithFormat:
          @"File maxBytes must be between 1 and %lu",
          (unsigned long)kMaximumReadBytes]];
    }
    return nil;
  }

  BOOL accessing = [url startAccessingSecurityScopedResource];
  NSNumber *size = nil;
  [url getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
  if (size != nil && size.unsignedLongLongValue > (unsigned long long)maxBytes) {
    if (accessing) [url stopAccessingSecurityScopedResource];
    if (error != NULL) {
      *error = [self errorWithMessage:[NSString stringWithFormat:
          @"File exceeds maxBytes (%ld)", (long)maxBytes]];
    }
    return nil;
  }
  NSData *data = [NSData dataWithContentsOfURL:url
                                      options:NSDataReadingMappedIfSafe
                                        error:error];
  if (accessing) {
    [url stopAccessingSecurityScopedResource];
  }
  if (data.length > (NSUInteger)maxBytes) {
    if (error != NULL) {
      *error = [self errorWithMessage:[NSString stringWithFormat:
          @"File exceeds maxBytes (%ld)", (long)maxBytes]];
    }
    return nil;
  }
  return data;
}

- (nullable NSString *)mimeTypeForIdentifier:(nullable NSString *)identifier {
  if (identifier.length == 0) {
    return nil;
  }
  CFStringRef tag = UTTypeCopyPreferredTagWithClass(
      (__bridge CFStringRef)identifier, kUTTagClassMIMEType);
  return CFBridgingRelease(tag);
}

- (NSError *)errorWithMessage:(NSString *)message {
  return [NSError errorWithDomain:@"LynxFileSystem"
                             code:1
                         userInfo:@{ NSLocalizedDescriptionKey : message }];
}

- (void)complete:(LynxCallbackBlock)callback
            value:(nullable id)value
            error:(nullable NSError *)error {
  NSString *result = [self resultJSONWithValue:value
                                         error:error.localizedDescription ?: @""];
  dispatch_async(dispatch_get_main_queue(), ^{
    callback(result);
  });
}

- (NSString *)resultJSONWithValue:(nullable id)value error:(NSString *)error {
  NSData *data = [NSJSONSerialization dataWithJSONObject:@{
    @"value" : value ?: NSNull.null,
    @"error" : error,
  } options:0 error:nil];
  if (data == nil) {
    return @"{\"value\":null,\"error\":\"Unable to encode FileSystem result\"}";
  }
  return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

@end
