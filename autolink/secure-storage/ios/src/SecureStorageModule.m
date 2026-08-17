#import "SecureStorageModule.h"

#import <Security/Security.h>

static NSString *const kService = @"lynx.secure.storage";
static const NSUInteger kMaxValueLength = 64 * 1024;

// The @LynxNativeModule annotation is what cocoapods-lynx-library scans for;
// it expands to a harmless ObjC forward declaration when compiled.
// Exported to Lynx as `SecureStorage`.
@LynxNativeModule("SecureStorage")
@implementation SecureStorageModule

+ (NSString *)name {
  return @"SecureStorage";
}

+ (NSDictionary<NSString *, NSString *> *)methodLookup {
  return @{
    @"setString" : NSStringFromSelector(@selector(setString:value:callback:)),
    @"getString" : NSStringFromSelector(@selector(getString:defaultValue:callback:)),
    @"remove" : NSStringFromSelector(@selector(remove:callback:)),
  };
}

- (void)setString:(NSString *)key
            value:(NSString *)value
         callback:(LynxCallbackBlock)callback {
  if (![self isValidKey:key]) {
    callback(@"Secure storage key must not be empty");
    return;
  }
  if (value.length > kMaxValueLength) {
    callback(@"Secure storage value is too large");
    return;
  }
  NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding];
  if (data == nil) {
    callback(@"Unable to encode the secure value");
    return;
  }
  NSDictionary *query = [self itemQueryForKey:key];
  OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, NULL);
  if (status == errSecSuccess) {
    NSDictionary *update = @{(id)kSecValueData : data};
    status = SecItemUpdate((__bridge CFDictionaryRef)query, (__bridge CFDictionaryRef)update);
  } else if (status == errSecItemNotFound) {
    NSMutableDictionary *add = [query mutableCopy];
    add[(id)kSecValueData] = data;
    // Device-only: the secret never migrates to backups or other devices.
    add[(id)kSecAttrAccessible] = (id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
    status = SecItemAdd((__bridge CFDictionaryRef)add, NULL);
  }
  if (status != errSecSuccess) {
    callback([NSString stringWithFormat:@"Unable to write the keychain item (%d)", (int)status]);
    return;
  }
  callback(@"");
}

- (void)getString:(NSString *)key
     defaultValue:(nullable NSString *)defaultValue
         callback:(LynxCallbackBlock)callback {
  if (![self isValidKey:key]) {
    callback(defaultValue ?: NSNull.null);
    return;
  }
  NSMutableDictionary *query = [[self itemQueryForKey:key] mutableCopy];
  query[(id)kSecReturnData] = @YES;
  query[(id)kSecMatchLimit] = (id)kSecMatchLimitOne;

  CFTypeRef result = NULL;
  OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
  if (status != errSecSuccess || result == NULL) {
    callback(defaultValue ?: NSNull.null);
    return;
  }
  NSString *value = [[NSString alloc] initWithData:CFBridgingRelease(result)
                                          encoding:NSUTF8StringEncoding];
  callback(value ?: defaultValue ?: NSNull.null);
}

- (void)remove:(NSString *)key callback:(LynxCallbackBlock)callback {
  if (![self isValidKey:key]) {
    callback(@"Secure storage key must not be empty");
    return;
  }
  OSStatus status = SecItemDelete((__bridge CFDictionaryRef)[self itemQueryForKey:key]);
  if (status != errSecSuccess && status != errSecItemNotFound) {
    callback([NSString stringWithFormat:@"Unable to remove the keychain item (%d)", (int)status]);
    return;
  }
  callback(@"");
}

- (NSDictionary *)itemQueryForKey:(NSString *)key {
  return @{
    (id)kSecClass : (id)kSecClassGenericPassword,
    (id)kSecAttrService : kService,
    (id)kSecAttrAccount : key,
  };
}

- (BOOL)isValidKey:(NSString *)key {
  return key.length > 0 && [key stringByTrimmingCharactersInSet:
      [NSCharacterSet whitespaceAndNewlineCharacterSet]].length > 0;
}

@end
