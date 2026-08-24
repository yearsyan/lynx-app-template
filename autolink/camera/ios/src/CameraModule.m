#import "CameraModule.h"

#import "CameraPhotoUtils.h"

#import <AVFoundation/AVFoundation.h>
#import <Lynx/LynxContext.h>
#import <UIKit/UIKit.h>

static NSString *const LynxCameraOutcomeSuccess = @"success";
static NSString *const LynxCameraOutcomeUserCancel = @"userCancel";
static NSString *const LynxCameraOutcomePermissionDenied = @"permissionDenied";
static NSString *const LynxCameraOutcomeUnavailable = @"unavailable";
static NSString *const LynxCameraOutcomeBusy = @"busy";

@interface CameraModule () <UIImagePickerControllerDelegate,
                            UINavigationControllerDelegate>
@end

// Exported to Lynx as `Camera`.
@LynxNativeModule("Camera")
@implementation CameraModule {
  LynxContext *_context;
  LynxCallbackBlock _callback;
  UIImagePickerController *_picker;
  NSString *_lens;
}

+ (NSString *)name {
  return @"Camera";
}

+ (NSDictionary<NSString *, NSString *> *)methodLookup {
  return @{
    @"takePhoto" : NSStringFromSelector(@selector(takePhoto:callback:)),
  };
}

- (instancetype)initWithLynxContext:(LynxContext *)context {
  self = [super init];
  if (self) {
    _context = context;
  }
  return self;
}

- (void)takePhoto:(NSDictionary *)options callback:(LynxCallbackBlock)callback {
  dispatch_async(dispatch_get_main_queue(), ^{
    NSString *lens = [options[@"lens"] isKindOfClass:NSString.class]
                         ? options[@"lens"]
                         : @"back";
    if (![lens isEqualToString:@"back"] && ![lens isEqualToString:@"front"]) {
      callback([self errorJSON:@"Camera lens must be back or front"]);
      return;
    }
    if (self->_callback != nil) {
      callback([self outcomeJSONWithCode:LynxCameraOutcomeBusy
                                   photo:nil
                                 message:@"Another system camera request is already active"]);
      return;
    }
    if (![UIImagePickerController
            isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]) {
      callback([self outcomeJSONWithCode:LynxCameraOutcomeUnavailable
                                   photo:nil
                                 message:@"The system camera is unavailable"]);
      return;
    }

    self->_callback = [callback copy];
    self->_lens = lens;
    AVAuthorizationStatus status =
        [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    if (status == AVAuthorizationStatusAuthorized) {
      [self presentCamera];
      return;
    }
    if (status == AVAuthorizationStatusNotDetermined) {
      __weak CameraModule *weakSelf = self;
      [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo
                               completionHandler:^(BOOL granted) {
        dispatch_async(dispatch_get_main_queue(), ^{
          CameraModule *strongSelf = weakSelf;
          if (strongSelf == nil || strongSelf->_callback == nil) {
            return;
          }
          if (granted) {
            [strongSelf presentCamera];
          } else {
            [strongSelf finishWithCode:LynxCameraOutcomePermissionDenied
                                 photo:nil
                               message:@"Camera access was not granted"];
          }
        });
      }];
      return;
    }
    [self finishWithCode:LynxCameraOutcomePermissionDenied
                   photo:nil
                 message:@"Camera access is denied"];
  });
}

- (void)presentCamera {
  UIViewController *presenter = [self presentingViewController];
  if (presenter == nil) {
    [self finishWithCode:LynxCameraOutcomeUnavailable
                   photo:nil
                 message:@"Unable to find a view controller for the system camera"];
    return;
  }
  UIImagePickerController *picker = [[UIImagePickerController alloc] init];
  picker.sourceType = UIImagePickerControllerSourceTypeCamera;
  picker.delegate = self;
  picker.modalPresentationStyle = UIModalPresentationFullScreen;
  UIImagePickerControllerCameraDevice preferred =
      [_lens isEqualToString:@"front"]
          ? UIImagePickerControllerCameraDeviceFront
          : UIImagePickerControllerCameraDeviceRear;
  if ([UIImagePickerController isCameraDeviceAvailable:preferred]) {
    picker.cameraDevice = preferred;
  }
  _picker = picker;
  [presenter presentViewController:picker animated:YES completion:nil];
}

- (void)imagePickerController:(UIImagePickerController *)picker
    didFinishPickingMediaWithInfo:
        (NSDictionary<UIImagePickerControllerInfoKey, id> *)info {
  UIImage *image = info[UIImagePickerControllerOriginalImage];
  [picker dismissViewControllerAnimated:YES completion:nil];
  _picker = nil;
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    NSError *error = nil;
    NSDictionary *photo = image == nil
                              ? nil
                              : LynxCameraWriteJPEG(image, 0.95, NO, &error);
    dispatch_async(dispatch_get_main_queue(), ^{
      if (photo == nil) {
        [self finishWithCode:LynxCameraOutcomeUnavailable
                       photo:nil
                     message:error.localizedDescription ?:
                                 @"Unable to save the captured photo"];
      } else {
        [self finishWithCode:LynxCameraOutcomeSuccess
                       photo:photo
                     message:@""];
      }
    });
  });
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
  [picker dismissViewControllerAnimated:YES completion:nil];
  _picker = nil;
  [self finishWithCode:LynxCameraOutcomeUserCancel
                 photo:nil
               message:@"The user cancelled the camera"];
}

- (void)finishWithCode:(NSString *)code
                 photo:(nullable NSDictionary *)photo
               message:(NSString *)message {
  LynxCallbackBlock callback = _callback;
  _callback = nil;
  _lens = nil;
  if (callback != nil) {
    callback([self outcomeJSONWithCode:code photo:photo message:message]);
  }
}

- (NSString *)outcomeJSONWithCode:(NSString *)code
                            photo:(nullable NSDictionary *)photo
                          message:(NSString *)message {
  NSData *data = [NSJSONSerialization dataWithJSONObject:@{
    @"error" : @"",
    @"value" : @{
      @"code" : code,
      @"photo" : photo ?: NSNull.null,
      @"message" : message ?: @"",
    },
  }
                                               options:0
                                                 error:nil];
  return data == nil
             ? [self errorJSON:@"Unable to encode the camera result"]
             : [[NSString alloc] initWithData:data
                                     encoding:NSUTF8StringEncoding];
}

- (NSString *)errorJSON:(NSString *)message {
  NSData *data = [NSJSONSerialization dataWithJSONObject:@{
    @"error" : message ?: @"Camera failed",
  }
                                               options:0
                                                 error:nil];
  return data == nil
             ? @"{\"error\":\"Unable to encode the camera result\"}"
             : [[NSString alloc] initWithData:data
                                     encoding:NSUTF8StringEncoding];
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

- (nullable UIViewController *)topViewController:
    (nullable UIViewController *)controller {
  if (controller.presentedViewController != nil) {
    return [self topViewController:controller.presentedViewController];
  }
  if ([controller isKindOfClass:UINavigationController.class]) {
    return [self topViewController:
        ((UINavigationController *)controller).visibleViewController];
  }
  if ([controller isKindOfClass:UITabBarController.class]) {
    return [self topViewController:
        ((UITabBarController *)controller).selectedViewController];
  }
  return controller;
}

- (void)destroy {
  dispatch_async(dispatch_get_main_queue(), ^{
    self->_callback = nil;
    [self->_picker dismissViewControllerAnimated:NO completion:nil];
    self->_picker = nil;
  });
}

@end
