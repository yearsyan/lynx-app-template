#import "KVModule.h"

#import <MMKV/MMKV.h>

static NSString *const kStorageID = @"lynx.native.kv";

// The @LynxNativeModule annotation is what cocoapods-lynx-library scans for;
// it expands to a harmless ObjC forward declaration when compiled.
// Exported to Lynx as `KV`.
@LynxNativeModule("KV")
@implementation KVModule {
  MMKV *_storage;
}

+ (NSString *)name {
  return @"KV";
}

+ (NSDictionary<NSString *, NSString *> *)methodLookup {
  return @{
    @"setString" : NSStringFromSelector(@selector(setString:value:callback:)),
    @"getString" : NSStringFromSelector(@selector(getString:defaultValue:callback:)),
    @"remove" : NSStringFromSelector(@selector(remove:callback:)),
    @"clear" : NSStringFromSelector(@selector(clear:)),
    @"contains" : NSStringFromSelector(@selector(contains:callback:)),
  };
}

- (instancetype)init {
  self = [super init];
  if (self) {
    _storage = [MMKV mmkvWithID:kStorageID];
  }
  return self;
}

- (void)setString:(NSString *)key
            value:(NSString *)value
         callback:(LynxCallbackBlock)callback {
  if (![self isValidKey:key] || ![_storage setString:value forKey:key]) {
    callback(@"Unable to persist MMKV key");
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
  NSString *value = [_storage getStringForKey:key defaultValue:defaultValue];
  callback(value ?: NSNull.null);
}

- (void)remove:(NSString *)key callback:(LynxCallbackBlock)callback {
  if (![self isValidKey:key]) {
    callback(@"MMKV key must not be empty");
    return;
  }
  [_storage removeValueForKey:key];
  callback(@"");
}

- (void)clear:(LynxCallbackBlock)callback {
  [_storage clearAll];
  callback(@"");
}

- (void)contains:(NSString *)key callback:(LynxCallbackBlock)callback {
  callback(@([self isValidKey:key] && [_storage containsKey:key]));
}

- (BOOL)isValidKey:(NSString *)key {
  return key.length > 0 && [key stringByTrimmingCharactersInSet:
      [NSCharacterSet whitespaceAndNewlineCharacterSet]].length > 0;
}

@end
