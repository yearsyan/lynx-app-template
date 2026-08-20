#import "PermissionsModule.h"

#import <AVFoundation/AVFoundation.h>
#import <Photos/Photos.h>
#import <UserNotifications/UserNotifications.h>

// The @LynxNativeModule annotation is what cocoapods-lynx-library scans for;
// it expands to a harmless ObjC forward declaration when compiled.
// Exported to Lynx as `Permissions`.
@LynxNativeModule("Permissions")
@implementation PermissionsModule

+ (NSString *)name {
  return @"Permissions";
}

+ (NSDictionary<NSString *, NSString *> *)methodLookup {
  return @{
    @"check" : NSStringFromSelector(@selector(check:callback:)),
    @"request" : NSStringFromSelector(@selector(request:callback:)),
  };
}

- (instancetype)initWithLynxContext:(LynxContext *)context {
  return [super init];
}

- (void)check:(NSDictionary<NSString *, id> *)permission callback:(LynxCallbackBlock)callback {
  NSString *type = [self parseType:permission];
  if (type == nil) {
    callback(@{ @"error" : @"Invalid permission request" });
    return;
  }
  [self resolveStatusForType:type
                      prompt:NO
                 completion:^(NSString *status) {
                   callback([PermissionsModule stateResultForStatus:status]);
                 }];
}

- (void)request:(NSDictionary<NSString *, id> *)permission callback:(LynxCallbackBlock)callback {
  NSString *type = [self parseType:permission];
  if (type == nil) {
    callback(@{ @"error" : @"Invalid permission request" });
    return;
  }
  [self resolveStatusForType:type
                      prompt:YES
                 completion:^(NSString *status) {
                   callback([PermissionsModule stateResultForStatus:status]);
                 }];
}

#pragma mark - Permission resolution

- (void)resolveStatusForType:(NSString *)type
                      prompt:(BOOL)prompt
                 completion:(void (^)(NSString *status))completion {
  if ([type isEqualToString:@"notifications"]) {
    void (^resolve)(void) = ^{
      UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
      if (prompt) {
        UNAuthorizationOptions options =
            UNAuthorizationOptionAlert | UNAuthorizationOptionSound | UNAuthorizationOptionBadge;
        [center requestAuthorizationWithOptions:options
                              completionHandler:^(
                                  BOOL granted, NSError *_Nullable error) {
                                completion(granted ? @"granted" : @"denied");
                              }];
      } else {
        [center getNotificationSettingsWithCompletionHandler:^(
                   UNNotificationSettings *_Nonnull settings) {
          completion(statusForAuthorization(settings.authorizationStatus));
        }];
      }
    };
    if (prompt) {
      // requestAuthorization prompts on the main thread.
      dispatch_async(dispatch_get_main_queue(), resolve);
    } else {
      resolve();
    }
    return;
  }

  if ([type isEqualToString:@"camera"]) {
    if (prompt) {
      [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo
                                 completionHandler:^(BOOL granted) {
                                   completion(granted ? @"granted" : @"denied");
                                 }];
    } else {
      completion(
          statusForAVAuthorization([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo]));
    }
    return;
  }

  if ([type isEqualToString:@"microphone"]) {
    if (prompt) {
      [[AVAudioSession sharedInstance]
          requestRecordPermission:^(BOOL granted) {
            completion(granted ? @"granted" : @"denied");
          }];
    } else {
      completion(
          statusForRecordPermission([[AVAudioSession sharedInstance] recordPermission]));
    }
    return;
  }

  // photoLibrary
  if (@available(iOS 14, *)) {
    if (prompt) {
      [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelReadWrite
                                                  handler:^(PHAuthorizationStatus status) {
                                                    completion(statusForPHAuthorization(status));
                                                  }];
    } else {
      completion(statusForPHAuthorization(
          [PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelReadWrite]));
    }
  } else {
    // iOS 13 has no limited photo access.
    if (prompt) {
      [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
        completion(statusForPHAuthorization(status));
      }];
    } else {
      completion(statusForPHAuthorization([PHPhotoLibrary authorizationStatus]));
    }
  }
}

#pragma mark - Mapping helpers

static NSString *statusForAuthorization(UNAuthorizationStatus status) {
  switch (status) {
    case UNAuthorizationStatusAuthorized:
    case UNAuthorizationStatusProvisional:
    case UNAuthorizationStatusEphemeral:
      return @"granted";
    case UNAuthorizationStatusDenied:
      return @"denied";
    case UNAuthorizationStatusNotDetermined:
      return @"notDetermined";
    default:
      return @"restricted";
  }
}

static NSString *statusForAVAuthorization(AVAuthorizationStatus status) {
  switch (status) {
    case AVAuthorizationStatusAuthorized:
      return @"granted";
    case AVAuthorizationStatusDenied:
      return @"denied";
    case AVAuthorizationStatusNotDetermined:
      return @"notDetermined";
    default:
      return @"restricted";
  }
}

static NSString *statusForRecordPermission(AVAudioSessionRecordPermission permission) {
  switch (permission) {
    case AVAudioSessionRecordPermissionGranted:
      return @"granted";
    case AVAudioSessionRecordPermissionDenied:
      return @"denied";
    default:
      // AVAudioSession cannot report parental-control restrictions.
      return @"notDetermined";
  }
}

static NSString *statusForPHAuthorization(PHAuthorizationStatus status) {
  switch (status) {
    case PHAuthorizationStatusAuthorized:
      return @"granted";
    case PHAuthorizationStatusLimited:
      return @"limited";
    case PHAuthorizationStatusDenied:
      return @"denied";
    case PHAuthorizationStatusNotDetermined:
      return @"notDetermined";
    default:
      return @"restricted";
  }
}

+ (NSDictionary<NSString *, id> *)stateResultForStatus:(NSString *)status {
  return @{@"value" : @{@"status" : status}};
}

- (nullable NSString *)parseType:(NSDictionary<NSString *, id> *)permission {
  if (![permission isKindOfClass:[NSDictionary class]]) {
    return nil;
  }
  NSString *type = permission[@"type"];
  if (![type isKindOfClass:[NSString class]]) {
    return nil;
  }
  if ([type isEqualToString:@"notifications"] || [type isEqualToString:@"camera"] ||
      [type isEqualToString:@"photoLibrary"] || [type isEqualToString:@"microphone"]) {
    return type;
  }
  return nil;
}

@end
