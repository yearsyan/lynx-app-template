#import "AlbumUtilsModule.h"

#import <Lynx/LynxContext.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import <Photos/Photos.h>
#import <PhotosUI/PhotosUI.h>
#import <UIKit/UIKit.h>

@interface AlbumUtilsModule () <PHPickerViewControllerDelegate,
                                   UIImagePickerControllerDelegate,
                                   UINavigationControllerDelegate>
@end

// Exported to Lynx as `AlbumUtils`.
@LynxNativeModule("AlbumUtils")
@implementation AlbumUtilsModule {
  LynxContext *_context;
  LynxCallbackBlock _callback;
  UIViewController *_pickerController;
  NSInteger _maxSelection;
}

+ (NSString *)name {
  return @"AlbumUtils";
}

+ (NSDictionary<NSString *, NSString *> *)methodLookup {
  return @{
    @"pick" : NSStringFromSelector(@selector(pick:callback:)),
    @"saveToAlbum" : NSStringFromSelector(@selector(saveToAlbum:callback:)),
  };
}

- (instancetype)initWithLynxContext:(LynxContext *)context {
  self = [super init];
  if (self) {
    _context = context;
  }
  return self;
}

- (void)pick:(NSInteger)maxSelection callback:(LynxCallbackBlock)callback {
  dispatch_async(dispatch_get_main_queue(), ^{
    if (maxSelection < 1 || maxSelection > 50) {
      callback([self resultJSONWithURIs:@[]
                                 error:@"Image picker maxSelection must be between 1 and 50"]);
      return;
    }
    if (self->_callback != nil) {
      callback([self resultJSONWithURIs:@[]
                                 error:@"Another image picker request is already active"]);
      return;
    }
    self->_callback = [callback copy];
    self->_maxSelection = maxSelection;
    if (@available(iOS 14.0, *)) {
      [self presentModernPicker];
    } else {
      [self requestLegacyPhotoAccessAndPresent];
    }
  });
}

- (void)saveToAlbum:(NSString *)uri callback:(LynxCallbackBlock)callback {
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    NSError *error = nil;
    NSURL *url = [self albumFileURL:uri error:&error];
    if (url != nil) {
      [PHPhotoLibrary.sharedPhotoLibrary
          performChangesAndWait:^{
            PHAssetCreationRequest *request = [PHAssetCreationRequest creationRequestForAsset];
            [request addResourceWithType:PHAssetResourceTypePhoto fileURL:url options:nil];
          }
          error:&error];
    }
    dispatch_async(dispatch_get_main_queue(), ^{
      NSString *message = error == nil
          ? @""
          : (error.localizedDescription.length > 0
                ? error.localizedDescription
                : @"Unable to save the image to the album");
      callback(message);
    });
  });
}

- (void)destroy {
  dispatch_async(dispatch_get_main_queue(), ^{
    self->_callback = nil;
    [self->_pickerController dismissViewControllerAnimated:NO completion:nil];
    self->_pickerController = nil;
  });
}

#pragma mark - Presentation

- (void)presentModernPicker API_AVAILABLE(ios(14.0)) {
  PHPickerConfiguration *configuration = [[PHPickerConfiguration alloc] init];
  configuration.filter = PHPickerFilter.imagesFilter;
  configuration.selectionLimit = _maxSelection;
  configuration.preferredAssetRepresentationMode =
      PHPickerConfigurationAssetRepresentationModeCurrent;
  PHPickerViewController *picker =
      [[PHPickerViewController alloc] initWithConfiguration:configuration];
  picker.delegate = self;
  [self presentPickerController:picker];
}

- (void)requestLegacyPhotoAccessAndPresent {
  if (_maxSelection > 1) {
    [self finishWithError:@"Selecting multiple images requires iOS 14 or later"];
    return;
  }
  PHAuthorizationStatus status = PHPhotoLibrary.authorizationStatus;
  if (status == PHAuthorizationStatusAuthorized) {
    [self presentLegacyPicker];
    return;
  }
  if (status == PHAuthorizationStatusNotDetermined) {
    __weak AlbumUtilsModule *weakSelf = self;
    [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus nextStatus) {
      dispatch_async(dispatch_get_main_queue(), ^{
        AlbumUtilsModule *strongSelf = weakSelf;
        if (strongSelf == nil || strongSelf->_callback == nil) {
          return;
        }
        if (nextStatus == PHAuthorizationStatusAuthorized) {
          [strongSelf presentLegacyPicker];
        } else {
          [strongSelf finishWithError:@"Photo library access was not granted"];
        }
      });
    }];
    return;
  }
  [self finishWithError:@"Photo library access is denied"];
}

- (void)presentLegacyPicker {
  if (![UIImagePickerController
          isSourceTypeAvailable:UIImagePickerControllerSourceTypePhotoLibrary]) {
    [self finishWithError:@"The system image picker is unavailable"];
    return;
  }
  UIImagePickerController *picker = [[UIImagePickerController alloc] init];
  picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
  picker.mediaTypes = @[ (__bridge NSString *)kUTTypeImage ];
  picker.delegate = self;
  [self presentPickerController:picker];
}

- (void)presentPickerController:(UIViewController *)picker {
  UIViewController *presenter = [self presentingViewController];
  if (presenter == nil) {
    [self finishWithError:@"Unable to find a view controller for the image picker"];
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

#pragma mark - PHPicker

- (void)picker:(PHPickerViewController *)picker
    didFinishPicking:(NSArray<PHPickerResult *> *)results API_AVAILABLE(ios(14.0)) {
  [picker dismissViewControllerAnimated:YES completion:nil];
  _pickerController = nil;
  if (results.count == 0) {
    [self finishWithURIs:@[]];
    return;
  }

  NSMutableArray *ordered = [NSMutableArray arrayWithCapacity:results.count];
  for (NSUInteger index = 0; index < results.count; index++) {
    [ordered addObject:NSNull.null];
  }
  NSLock *lock = [[NSLock alloc] init];
  __block NSString *firstError = nil;
  dispatch_group_t group = dispatch_group_create();
  [results enumerateObjectsUsingBlock:^(PHPickerResult *result,
                                        NSUInteger index,
                                        BOOL *stop) {
    NSItemProvider *provider = result.itemProvider;
    NSString *typeIdentifier = [self imageTypeIdentifierForProvider:provider];
    if (typeIdentifier == nil) {
      if (firstError == nil) {
        firstError = @"The selected image has no readable representation";
      }
      return;
    }
    dispatch_group_enter(group);
    [provider loadFileRepresentationForTypeIdentifier:typeIdentifier
                                    completionHandler:^(NSURL *sourceURL, NSError *error) {
      NSError *copyError = error;
      NSURL *destination = nil;
      if (sourceURL != nil && copyError == nil) {
        destination = [self copyURLToCache:sourceURL kind:@"images" error:&copyError];
      }
      [lock lock];
      if (destination != nil) {
        ordered[index] = destination.absoluteString;
      } else if (firstError == nil) {
        firstError = copyError.localizedDescription ?: @"Unable to load a selected image";
      }
      [lock unlock];
      dispatch_group_leave(group);
    }];
  }];

  dispatch_group_notify(group, dispatch_get_main_queue(), ^{
    NSMutableArray<NSString *> *uris = [NSMutableArray array];
    for (id value in ordered) {
      if ([value isKindOfClass:NSString.class]) {
        [uris addObject:value];
      }
    }
    if (uris.count == 0 && firstError.length > 0) {
      [self finishWithError:firstError];
    } else {
      [self finishWithURIs:uris];
    }
  });
}

- (nullable NSString *)imageTypeIdentifierForProvider:(NSItemProvider *)provider {
  for (NSString *identifier in provider.registeredTypeIdentifiers) {
    if (UTTypeConformsTo((__bridge CFStringRef)identifier, kUTTypeImage)) {
      return identifier;
    }
  }
  NSString *imageType = (__bridge NSString *)kUTTypeImage;
  return [provider hasItemConformingToTypeIdentifier:imageType] ? imageType : nil;
}

#pragma mark - UIImagePickerController

- (void)imagePickerController:(UIImagePickerController *)picker
    didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey, id> *)info {
  NSURL *sourceURL = info[UIImagePickerControllerImageURL];
  UIImage *image = info[UIImagePickerControllerOriginalImage];
  [picker dismissViewControllerAnimated:YES completion:nil];
  _pickerController = nil;

  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    NSError *error = nil;
    NSURL *destination = sourceURL == nil
        ? [self writeImageToCache:image error:&error]
        : [self copyURLToCache:sourceURL kind:@"images" error:&error];
    dispatch_async(dispatch_get_main_queue(), ^{
      if (destination == nil) {
        [self finishWithError:error.localizedDescription ?: @"Unable to load the selected image"];
      } else {
        [self finishWithURIs:@[ destination.absoluteString ]];
      }
    });
  });
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
  [picker dismissViewControllerAnimated:YES completion:nil];
  _pickerController = nil;
  [self finishWithURIs:@[]];
}

#pragma mark - Files and results

- (nullable NSURL *)albumFileURL:(NSString *)uri error:(NSError **)error {
  NSURL *url = [NSURL URLWithString:[uri stringByTrimmingCharactersInSet:
      NSCharacterSet.whitespaceAndNewlineCharacterSet]];
  if (url == nil || !url.isFileURL) {
    if (error != NULL) {
      *error = [NSError errorWithDomain:@"LynxAlbumUtils"
                                   code:3
                               userInfo:@{NSLocalizedDescriptionKey :
                                          @"AlbumUtils saves file:// image URIs on iOS"}];
    }
    return nil;
  }
  BOOL isDirectory = NO;
  if (![NSFileManager.defaultManager fileExistsAtPath:url.path isDirectory:&isDirectory]
      || isDirectory) {
    if (error != NULL) {
      *error = [NSError errorWithDomain:@"LynxAlbumUtils"
                                   code:4
                               userInfo:@{NSLocalizedDescriptionKey :
                                          @"The image file does not exist"}];
    }
    return nil;
  }
  return url;
}

- (nullable NSURL *)writeImageToCache:(nullable UIImage *)image
                                 error:(NSError **)error {
  if (image == nil) {
    if (error != NULL) {
      *error = [NSError errorWithDomain:@"LynxAlbumUtils"
                                   code:1
                               userInfo:@{NSLocalizedDescriptionKey : @"No image data was returned"}];
    }
    return nil;
  }
  NSData *data = UIImageJPEGRepresentation(image, 0.95);
  if (data == nil) {
    if (error != NULL) {
      *error = [NSError errorWithDomain:@"LynxAlbumUtils"
                                   code:2
                               userInfo:@{NSLocalizedDescriptionKey : @"Unable to encode the selected image"}];
    }
    return nil;
  }
  NSURL *directory = [self cacheDirectoryForKind:@"images" error:error];
  if (directory == nil) {
    return nil;
  }
  NSURL *destination = [directory URLByAppendingPathComponent:
      [NSString stringWithFormat:@"%@.jpg", NSUUID.UUID.UUIDString]];
  return [data writeToURL:destination options:NSDataWritingAtomic error:error]
      ? destination
      : nil;
}

- (nullable NSURL *)copyURLToCache:(NSURL *)sourceURL
                              kind:(NSString *)kind
                             error:(NSError **)error {
  NSURL *directory = [self cacheDirectoryForKind:kind error:error];
  if (directory == nil) {
    return nil;
  }
  NSString *name = sourceURL.lastPathComponent.length > 0
      ? sourceURL.lastPathComponent
      : @"image";
  NSURL *destination = [directory URLByAppendingPathComponent:
      [NSString stringWithFormat:@"%@-%@", NSUUID.UUID.UUIDString, name]];
  return [[NSFileManager defaultManager] copyItemAtURL:sourceURL
                                                toURL:destination
                                                error:error]
      ? destination
      : nil;
}

- (nullable NSURL *)cacheDirectoryForKind:(NSString *)kind
                                     error:(NSError **)error {
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
      URLByAppendingPathComponent:kind];
  return [[NSFileManager defaultManager] createDirectoryAtURL:directory
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:error]
      ? directory
      : nil;
}

- (void)finishWithURIs:(NSArray<NSString *> *)uris {
  [self finishWithResult:[self resultJSONWithURIs:uris error:@""]];
}

- (void)finishWithError:(NSString *)error {
  [self finishWithResult:[self resultJSONWithURIs:@[] error:error]];
}

- (void)finishWithResult:(NSString *)result {
  LynxCallbackBlock callback = _callback;
  _callback = nil;
  if (callback != nil) {
    callback(result);
  }
}

- (NSString *)resultJSONWithURIs:(NSArray<NSString *> *)uris
                            error:(NSString *)error {
  NSData *data = [NSJSONSerialization dataWithJSONObject:@{
    @"uris" : uris,
    @"error" : error,
  } options:0 error:nil];
  if (data == nil) {
    return @"{\"uris\":[],\"error\":\"Unable to encode image picker result\"}";
  }
  return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

@end
