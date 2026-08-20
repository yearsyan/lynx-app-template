#import "LocalNotificationModule.h"

#import <UserNotifications/UserNotifications.h>

/// Presents notifications as banners while the app is in the foreground, so
/// demo and chat-style notifications are visible without backgrounding the
/// app. Kept alive by a static reference on the module class.
@interface LocalNotificationCenterDelegate
    : NSObject <UNUserNotificationCenterDelegate>
@end

@implementation LocalNotificationCenterDelegate

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
       willPresentNotification:(UNNotification *)notification
         withCompletionHandler:
             (void (^)(UNNotificationPresentationOptions options))completionHandler {
  UNNotificationPresentationOptions options = 0;
  if (@available(iOS 14.0, *)) {
    options = UNNotificationPresentationOptionBanner | UNNotificationPresentationOptionList |
              UNNotificationPresentationOptionSound;
  } else {
    options = UNNotificationPresentationOptionAlert | UNNotificationPresentationOptionSound;
  }
  completionHandler(options);
}

@end

// The @LynxNativeModule annotation is what cocoapods-lynx-library scans for;
// it expands to a harmless ObjC forward declaration when compiled.
// Exported to Lynx as `LocalNotification`.
@LynxNativeModule("LocalNotification")
@implementation LocalNotificationModule

+ (NSString *)name {
  return @"LocalNotification";
}

+ (NSDictionary<NSString *, NSString *> *)methodLookup {
  return @{
    @"notify" : NSStringFromSelector(@selector(notify:callback:)),
    @"cancel" : NSStringFromSelector(@selector(cancel:callback:)),
    @"cancelAll" : NSStringFromSelector(@selector(cancelAll:)),
  };
}

- (instancetype)initWithLynxContext:(LynxContext *)context {
  self = [super init];
  if (self != nil) {
    [LocalNotificationModule installCenterDelegateIfNeeded];
  }
  return self;
}

/// Installs the foreground-presentation delegate exactly once per process.
+ (void)installCenterDelegateIfNeeded {
  static LocalNotificationCenterDelegate *delegate = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    delegate = [[LocalNotificationCenterDelegate alloc] init];
    [UNUserNotificationCenter currentNotificationCenter].delegate = delegate;
  });
}

- (void)notify:(NSDictionary<NSString *, id> *)rawOptions
      callback:(LynxCallbackBlock)callback {
  NSDictionary<NSString *, id> *options = [self parseOptions:rawOptions];
  if (options == nil) {
    callback(@{ @"error" : @"Invalid notification options" });
    return;
  }
  UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
  [center getNotificationSettingsWithCompletionHandler:^(
           UNNotificationSettings *_Nonnull settings) {
    switch (settings.authorizationStatus) {
      case UNAuthorizationStatusAuthorized:
      case UNAuthorizationStatusProvisional:
      case UNAuthorizationStatusEphemeral:
        break;
      default:
        callback([LocalNotificationModule
            outcomeResultForCode:@"permissionDenied"
                        message:@"Notifications are not authorized; request the"
                                 @" notification permission (Permissions module) or"
                                 @" enable them in system settings"]);
        return;
    }

    UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
    content.title = options[@"title"];
    content.body = options[@"body"] ?: @"";
    if ([options[@"sound"] boolValue]) {
      content.sound = [UNNotificationSound defaultSound];
    }

    UNNotificationRequest *request;
    NSString *identifier = options[@"id"];
    NSArray<NSString *> *identifiers = @[ identifier ];
    // The system replaces pending requests with the same identifier, but a
    // previously delivered notification must be removed explicitly.
    [center removePendingNotificationRequestsWithIdentifiers:identifiers];
    [center removeDeliveredNotificationsWithIdentifiers:identifiers];
    NSNumber *delayMs = options[@"delayMs"];
    if ([delayMs isKindOfClass:[NSNumber class]] && delayMs.doubleValue > 0) {
      UNTimeIntervalNotificationTrigger *trigger =
          [UNTimeIntervalNotificationTrigger triggerWithTimeInterval:delayMs.doubleValue / 1000.0
                                                              repeats:NO];
      request = [UNNotificationRequest requestWithIdentifier:identifier
                                                      content:content
                                                      trigger:trigger];
    } else {
      request = [UNNotificationRequest requestWithIdentifier:identifier
                                                      content:content
                                                      trigger:nil];
    }
    [center addNotificationRequest:request
             withCompletionHandler:^(NSError *_Nullable error) {
               if (error != nil) {
                 callback([LocalNotificationModule outcomeResultForCode:@"unavailable"
                                                                  message:error.localizedDescription]);
                 return;
               }
               callback([LocalNotificationModule outcomeResultForCode:@"success" message:@""]);
             }];
  }];
}

- (void)cancel:(NSString *)identifier callback:(LynxCallbackBlock)callback {
  if (identifier.length == 0) {
    callback(@"LocalNotification id must not be empty");
    return;
  }
  UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
  NSArray<NSString *> *identifiers = @[ identifier ];
  [center removePendingNotificationRequestsWithIdentifiers:identifiers];
  [center removeDeliveredNotificationsWithIdentifiers:identifiers];
  callback(@"");
}

- (void)cancelAll:(LynxCallbackBlock)callback {
  UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
  [center removeAllPendingNotificationRequests];
  [center removeAllDeliveredNotifications];
  callback(@"");
}

+ (NSDictionary<NSString *, id> *)outcomeResultForCode:(NSString *)code
                                                message:(NSString *)message {
  return @{@"value" : @{@"code" : code, @"message" : message ?: @""}};
}

- (nullable NSDictionary<NSString *, id> *)parseOptions:
    (NSDictionary<NSString *, id> *)options {
  if (![options isKindOfClass:[NSDictionary class]]) {
    return nil;
  }
  NSString *identifier = options[@"id"];
  NSString *title = options[@"title"];
  if (![identifier isKindOfClass:[NSString class]] || identifier.length == 0 ||
      ![title isKindOfClass:[NSString class]] || title.length == 0) {
    return nil;
  }
  NSNumber *delayMs = options[@"delayMs"];
  if (delayMs != nil &&
      (![delayMs isKindOfClass:[NSNumber class]] || delayMs.doubleValue < 0 ||
       delayMs.doubleValue > 7 * 24 * 60 * 60 * 1000)) {
    return nil;
  }
  return options;
}

@end
