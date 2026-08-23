#import "StorageModule.h"

#import <MMKV/MMKV.h>
#import <os/lock.h>
#import <Security/Security.h>

static NSString *const kStorageID = @"lynx.native.kv";
static NSString *const kService = @"lynx.secure.storage";
static const NSUInteger kMaxValueLength = 64 * 1024;

// Process-wide overlay mirroring the shared MMKV instance (module instances
// are per Lynx context, the store is not). Entries shadow MMKV until a
// persisted write or remove drops them.
static NSMutableDictionary<NSString *, NSString *> *kMemoryOverlay;
static os_unfair_lock kMemoryOverlayLock = OS_UNFAIR_LOCK_INIT;

static NSString *MemoryOverlayGet(NSString *key) {
  os_unfair_lock_lock(&kMemoryOverlayLock);
  NSString *value = kMemoryOverlay[key];
  os_unfair_lock_unlock(&kMemoryOverlayLock);
  return value;
}

static void MemoryOverlaySet(NSString *key, NSString *value) {
  os_unfair_lock_lock(&kMemoryOverlayLock);
  if (kMemoryOverlay == nil) {
    kMemoryOverlay = [NSMutableDictionary new];
  }
  kMemoryOverlay[key] = value;
  os_unfair_lock_unlock(&kMemoryOverlayLock);
}

static void MemoryOverlayRemove(NSString *key) {
  os_unfair_lock_lock(&kMemoryOverlayLock);
  [kMemoryOverlay removeObjectForKey:key];
  os_unfair_lock_unlock(&kMemoryOverlayLock);
}

static void MemoryOverlayClear(void) {
  os_unfair_lock_lock(&kMemoryOverlayLock);
  [kMemoryOverlay removeAllObjects];
  os_unfair_lock_unlock(&kMemoryOverlayLock);
}

static BOOL MemoryOverlayContains(NSString *key) {
  os_unfair_lock_lock(&kMemoryOverlayLock);
  BOOL contains = kMemoryOverlay[key] != nil;
  os_unfair_lock_unlock(&kMemoryOverlayLock);
  return contains;
}

static void EnsureMMKVInitialized(void) {
  static dispatch_once_t onceToken;
  void (^initialize)(void) = ^{
    dispatch_once(&onceToken, ^{
      [MMKV initializeMMKV:nil];
    });
  };
  if ([NSThread isMainThread]) {
    initialize();
  } else {
    // MMKV requires process bootstrap on the main thread. Lynx modules can be
    // constructed on the TASM thread, so keep this detail inside the
    // autolinked library instead of making every host repeat it.
    dispatch_sync(dispatch_get_main_queue(), initialize);
  }
}

// The @LynxNativeModule annotation is what cocoapods-lynx-library scans for;
// it expands to a harmless ObjC forward declaration when compiled.
// Exported to Lynx as `Storage`. The KV store also keeps a process-wide
// in-memory overlay: writes with inMemory=YES land only in the overlay
// (shadowing the MMKV value until the process dies) while persisted writes
// drop the overlay entry first; reads, remove, clear and contains all check
// the overlay before MMKV.
@LynxNativeModule("Storage")
@implementation StorageModule {
  MMKV *_storage;
}

+ (NSString *)name {
  return @"Storage";
}

+ (NSDictionary<NSString *, NSString *> *)methodLookup {
  return @{
    @"setString" : NSStringFromSelector(@selector(setString:value:callback:inMemory:)),
    @"getString" : NSStringFromSelector(@selector(getString:defaultValue:callback:)),
    @"getStringOrNull" : NSStringFromSelector(@selector(getStringOrNull:callback:)),
    @"remove" : NSStringFromSelector(@selector(remove:callback:)),
    @"clear" : NSStringFromSelector(@selector(clear:)),
    @"contains" : NSStringFromSelector(@selector(contains:callback:)),
    @"secureSetString" : NSStringFromSelector(@selector(secureSetString:value:callback:)),
    @"secureGetString" : NSStringFromSelector(@selector(secureGetString:defaultValue:callback:)),
    @"secureGetStringOrNull" : NSStringFromSelector(@selector(secureGetStringOrNull:callback:)),
    @"secureRemove" : NSStringFromSelector(@selector(secureRemove:callback:)),
  };
}

- (instancetype)init {
  self = [super init];
  if (self) {
    EnsureMMKVInitialized();
    _storage = [MMKV mmkvWithID:kStorageID];
  }
  return self;
}

#pragma mark - Shared MMKV-backed KV store

- (void)setString:(NSString *)key
            value:(NSString *)value
         callback:(LynxCallbackBlock)callback
         inMemory:(BOOL)inMemory {
  if (inMemory) {
    // Overlay-only write: the MMKV copy keeps its previous value.
    if (![self isValidKey:key] || value == nil) {
      callback(@"Unable to set the in-memory value");
      return;
    }
    MemoryOverlaySet(key, value);
    callback(@"");
    return;
  }
  // Persisted writes make MMKV authoritative again.
  MemoryOverlayRemove(key);
  if (![self isValidKey:key] || ![_storage setString:value forKey:key]) {
    callback(@"Unable to persist MMKV key");
    return;
  }
  callback(@"");
}

- (void)getString:(NSString *)key
     defaultValue:(NSString *)defaultValue
         callback:(LynxCallbackBlock)callback {
  [self readString:key defaultValue:defaultValue callback:callback];
}

- (void)getStringOrNull:(NSString *)key callback:(LynxCallbackBlock)callback {
  [self readString:key defaultValue:nil callback:callback];
}

- (void)readString:(NSString *)key
      defaultValue:(nullable NSString *)defaultValue
          callback:(LynxCallbackBlock)callback {
  if (![self isValidKey:key]) {
    callback(defaultValue ?: NSNull.null);
    return;
  }
  NSString *overlay = MemoryOverlayGet(key);
  if (overlay != nil) {
    callback(overlay);
    return;
  }
  NSString *value = [_storage getStringForKey:key defaultValue:defaultValue];
  callback(value ?: NSNull.null);
}

- (void)remove:(NSString *)key callback:(LynxCallbackBlock)callback {
  if (![self isValidKey:key]) {
    callback(@"MMKV key must not be empty");
    return;
  }
  [_storage removeValueForKey:key];
  MemoryOverlayRemove(key);
  callback(@"");
}

- (void)clear:(LynxCallbackBlock)callback {
  [_storage clearAll];
  MemoryOverlayClear();
  callback(@"");
}

- (void)contains:(NSString *)key callback:(LynxCallbackBlock)callback {
  callback(@([self isValidKey:key]
      && (MemoryOverlayContains(key) || [_storage containsKey:key])));
}

#pragma mark - Small-secret secure store

- (void)secureSetString:(NSString *)key
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

- (void)secureGetString:(NSString *)key
           defaultValue:(NSString *)defaultValue
               callback:(LynxCallbackBlock)callback {
  [self readSecureString:key defaultValue:defaultValue callback:callback];
}

- (void)secureGetStringOrNull:(NSString *)key callback:(LynxCallbackBlock)callback {
  [self readSecureString:key defaultValue:nil callback:callback];
}

- (void)readSecureString:(NSString *)key
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

- (void)secureRemove:(NSString *)key callback:(LynxCallbackBlock)callback {
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

#pragma mark - Helpers

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
