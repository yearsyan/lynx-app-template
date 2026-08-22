#import "BiometricModule.h"

#import <LocalAuthentication/LocalAuthentication.h>
#import <Security/Security.h>
#import <TargetConditionals.h>

static NSString *const kPolicyWeak = @"biometricWeak";
static NSString *const kPolicyStrong = @"biometricStrong";
static NSString *const kPolicyDeviceOwner = @"deviceOwnerAuthentication";
static NSString *const kSigningKeyPrefix = @"lynx.biometric.signing.v2.";
static NSString *const kSigningDomain = @"LYNX_BIOMETRIC_V2";

static NSString *reasonForLAError(NSError *_Nullable error, NSString *fallback);
static NSString *outcomeForLAError(NSError *_Nullable error);
static NSString *messageForCFError(CFErrorRef _Nullable error,
                                   NSString *fallback);
static NSDictionary<NSString *, id> *_Nullable parseJSONObject(NSString *json);
static NSDictionary<NSString *, id> *_Nullable parsePromptOptions(
    NSString *json, BOOL includePolicy);
static NSDictionary<NSString *, id> *_Nullable parseKeyCreateOptions(NSString *json);
static NSDictionary<NSString *, id> *_Nullable parseSignOptions(NSString *json);
static NSString *_Nullable policyFromOptions(NSDictionary<NSString *, id> *options);
static NSString *_Nullable keyIDFromOptions(NSString *json);
static NSString *_Nullable scopeFromKeyID(NSString *keyID);
static NSData *signingKeyTag(NSString *keyID);
static SecKeyRef _Nullable copySigningKey(NSString *keyID,
                                          LAContext *_Nullable context,
                                          OSStatus *statusOut);
static OSStatus deleteSigningKeyItem(NSString *keyID);
static NSData *_Nullable exportPublicPoint(SecKeyRef privateKey);
static NSString *securityLevelForKey(SecKeyRef key);
static NSData *_Nullable ecdsaDERToRaw(NSData *der);
static BOOL readDERLength(const uint8_t *bytes, NSUInteger total,
                          NSUInteger *offset, NSUInteger *value);
static NSData *_Nullable readDERInteger(const uint8_t *bytes, NSUInteger total,
                                        NSUInteger *offset);
static NSString *JSONEnvelope(NSDictionary<NSString *, id> *value);

@interface BiometricModule ()
+ (NSString *)outcomeJSONForCode:(NSString *)code
                         message:(NSString *)message
                          policy:(NSString *)policy;
+ (NSString *)keyJSONForCode:(NSString *)code
                     message:(NSString *)message
                       keyID:(nullable NSString *)keyID
                       scope:(nullable NSString *)scope
                   publicKey:(nullable NSString *)publicKey
               securityLevel:(NSString *)securityLevel;
+ (NSString *)deleteJSONForCode:(NSString *)code
                        message:(NSString *)message
                          keyID:(NSString *)keyID;
+ (NSString *)signatureJSONForCode:(NSString *)code
                           message:(NSString *)message
                             keyID:(NSString *)keyID
                         signature:(nullable NSString *)signature;
@end

@LynxNativeModule("Biometric")
@implementation BiometricModule {
  BOOL _promptActive;
}

+ (NSString *)name {
  return @"Biometric";
}

+ (NSDictionary<NSString *, NSString *> *)methodLookup {
  return @{
    @"checkSupport" : NSStringFromSelector(@selector(checkSupport:callback:)),
    @"authenticate" : NSStringFromSelector(@selector(authenticate:callback:)),
    @"createSigningKey" : NSStringFromSelector(@selector(createSigningKey:callback:)),
    @"getSigningKey" : NSStringFromSelector(@selector(getSigningKey:callback:)),
    @"deleteSigningKey" : NSStringFromSelector(@selector(deleteSigningKey:callback:)),
    @"signChallenge" : NSStringFromSelector(@selector(signChallenge:callback:)),
  };
}

#pragma mark - Local authentication

- (void)checkSupport:(NSString *)optionsJSON callback:(LynxCallbackBlock)callback {
  NSDictionary<NSString *, id> *options = parseJSONObject(optionsJSON);
  NSString *policy = policyFromOptions(options);
  if (options == nil || policy == nil) {
    callback(@"{\"error\":\"Invalid biometric support options\"}");
    return;
  }
  dispatch_async(dispatch_get_main_queue(), ^{
    callback([self supportJSONForPolicy:policy]);
  });
}

- (void)authenticate:(NSString *)optionsJSON callback:(LynxCallbackBlock)callback {
  NSDictionary<NSString *, id> *options = parsePromptOptions(optionsJSON, YES);
  if (options == nil) {
    callback(@"{\"error\":\"Invalid biometric options\"}");
    return;
  }
  NSString *policy = options[@"policy"];
  if (![self beginPrompt]) {
    callback([BiometricModule outcomeJSONForCode:@"busy"
                                         message:@"Another authentication request is already active"
                                          policy:policy]);
    return;
  }

  dispatch_async(dispatch_get_main_queue(), ^{
    LAContext *context = [[LAContext alloc] init];
    context.localizedFallbackTitle = @"";
    NSString *cancelButtonText = options[@"cancelButtonText"];
    if ([cancelButtonText isKindOfClass:[NSString class]]) {
      context.localizedCancelTitle = cancelButtonText;
    }
    LAPolicy laPolicy = [policy isEqualToString:kPolicyDeviceOwner]
                            ? LAPolicyDeviceOwnerAuthentication
                            : LAPolicyDeviceOwnerAuthenticationWithBiometrics;
    [context evaluatePolicy:laPolicy
             localizedReason:options[@"reason"]
                       reply:^(BOOL success, NSError *_Nullable error) {
                         [self endPrompt];
                         NSString *code = success ? @"success" : outcomeForLAError(error);
                         NSString *message = success ? @"" : error.localizedDescription ?: @"";
                         callback([BiometricModule outcomeJSONForCode:code
                                                               message:message
                                                                policy:policy]);
                       }];
  });
}

- (BOOL)beginPrompt {
  @synchronized(self) {
    if (_promptActive) return NO;
    _promptActive = YES;
    return YES;
  }
}

- (void)endPrompt {
  @synchronized(self) {
    _promptActive = NO;
  }
}

#pragma mark - V2 signing keys

- (void)createSigningKey:(NSString *)optionsJSON callback:(LynxCallbackBlock)callback {
  NSDictionary<NSString *, id> *options = parseKeyCreateOptions(optionsJSON);
  if (options == nil) {
    callback(@"{\"error\":\"Invalid biometric key options\"}");
    return;
  }
  dispatch_async(dispatch_get_main_queue(), ^{
    LAContext *probe = [[LAContext alloc] init];
    NSError *probeError = nil;
    if (![probe canEvaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics
                            error:&probeError]) {
      callback([BiometricModule keyJSONForCode:reasonForLAError(probeError, @"notSupported")
                                       message:probeError.localizedDescription ?: @""
                                         keyID:nil
                                         scope:nil
                                     publicKey:nil
                                 securityLevel:@"unknown"]);
      return;
    }

    NSString *scope = options[@"scope"];
    NSString *keyID = [NSString stringWithFormat:@"%@~%@", scope,
                                                 [NSUUID UUID].UUIDString.lowercaseString];
    NSData *tag = signingKeyTag(keyID);
    CFErrorRef accessError = NULL;
    SecAccessControlRef accessControl = SecAccessControlCreateWithFlags(
        kCFAllocatorDefault, kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        kSecAccessControlPrivateKeyUsage | kSecAccessControlBiometryCurrentSet,
        &accessError);
    if (accessControl == NULL) {
      NSString *message = messageForCFError(
          accessError, @"Unable to create key access control");
      callback([BiometricModule keyJSONForCode:@"unknown"
                                       message:message
                                         keyID:nil
                                         scope:nil
                                     publicKey:nil
                                 securityLevel:@"unknown"]);
      return;
    }
    if (accessError != NULL) CFRelease(accessError);

    NSDictionary *privateAttrs = @{
      (id)kSecAttrIsPermanent : @YES,
      (id)kSecAttrApplicationTag : tag,
      (id)kSecAttrAccessControl : (__bridge id)accessControl,
    };
    NSDictionary *secureEnclaveAttrs = @{
      (id)kSecAttrKeyType : (id)kSecAttrKeyTypeECSECPrimeRandom,
      (id)kSecAttrKeySizeInBits : @256,
      (id)kSecPrivateKeyAttrs : privateAttrs,
      (id)kSecAttrTokenID : (id)kSecAttrTokenIDSecureEnclave,
    };

    CFErrorRef createError = NULL;
    SecKeyRef privateKey = SecKeyCreateRandomKey(
        (__bridge CFDictionaryRef)secureEnclaveAttrs, &createError);
    NSString *securityLevel = @"secureHardware";
#if TARGET_OS_SIMULATOR
    if (privateKey == NULL) {
      if (createError != NULL) {
        CFRelease(createError);
        createError = NULL;
      }
      NSMutableDictionary *softwareAttrs = [secureEnclaveAttrs mutableCopy];
      [softwareAttrs removeObjectForKey:(id)kSecAttrTokenID];
      privateKey = SecKeyCreateRandomKey(
          (__bridge CFDictionaryRef)softwareAttrs, &createError);
      securityLevel = @"software";
    }
#endif
    CFRelease(accessControl);
    if (privateKey == NULL) {
      NSString *message = messageForCFError(
          createError, @"Unable to create Secure Enclave key");
      callback([BiometricModule keyJSONForCode:@"notSupported"
                                       message:message
                                         keyID:nil
                                         scope:nil
                                     publicKey:nil
                                 securityLevel:@"unknown"]);
      return;
    }
    if (createError != NULL) CFRelease(createError);

    NSData *point = exportPublicPoint(privateKey);
    CFRelease(privateKey);
    if (point.length != 65 || ((const uint8_t *)point.bytes)[0] != 0x04) {
      deleteSigningKeyItem(keyID);
      callback([BiometricModule keyJSONForCode:@"unknown"
                                       message:@"Unable to export the public key"
                                         keyID:nil
                                         scope:nil
                                     publicKey:nil
                                 securityLevel:@"unknown"]);
      return;
    }
    callback([BiometricModule keyJSONForCode:@"success"
                                     message:@""
                                       keyID:keyID
                                       scope:scope
                                   publicKey:[point base64EncodedStringWithOptions:0]
                               securityLevel:securityLevel]);
  });
}

- (void)getSigningKey:(NSString *)optionsJSON callback:(LynxCallbackBlock)callback {
  NSString *keyID = keyIDFromOptions(optionsJSON);
  if (keyID == nil) {
    callback(@"{\"error\":\"Invalid biometric key options\"}");
    return;
  }
  dispatch_async(dispatch_get_main_queue(), ^{
    OSStatus status = errSecSuccess;
    SecKeyRef privateKey = copySigningKey(keyID, nil, &status);
    if (privateKey == NULL) {
      NSString *code = status == errSecItemNotFound ? @"keyNotFound" : @"unknown";
      NSString *message = status == errSecItemNotFound
                              ? @"No signing key with this keyId exists"
                              : [NSString stringWithFormat:@"Unable to read signing key (%d)",
                                                         (int)status];
      callback([BiometricModule keyJSONForCode:code
                                       message:message
                                         keyID:nil
                                         scope:nil
                                     publicKey:nil
                                 securityLevel:@"unknown"]);
      return;
    }
    NSData *point = exportPublicPoint(privateKey);
    NSString *securityLevel = securityLevelForKey(privateKey);
    CFRelease(privateKey);
    if (point.length != 65 || ((const uint8_t *)point.bytes)[0] != 0x04) {
      callback([BiometricModule keyJSONForCode:@"unknown"
                                       message:@"Unable to export the public key"
                                         keyID:nil
                                         scope:nil
                                     publicKey:nil
                                 securityLevel:@"unknown"]);
      return;
    }
    callback([BiometricModule keyJSONForCode:@"success"
                                     message:@""
                                       keyID:keyID
                                       scope:scopeFromKeyID(keyID)
                                   publicKey:[point base64EncodedStringWithOptions:0]
                               securityLevel:securityLevel]);
  });
}

- (void)deleteSigningKey:(NSString *)optionsJSON callback:(LynxCallbackBlock)callback {
  NSString *keyID = keyIDFromOptions(optionsJSON);
  if (keyID == nil) {
    callback(@"{\"error\":\"Invalid biometric key options\"}");
    return;
  }
  if (![self beginPrompt]) {
    callback([BiometricModule deleteJSONForCode:@"busy"
                                        message:@"Another authentication request is already active"
                                          keyID:keyID]);
    return;
  }
  dispatch_async(dispatch_get_main_queue(), ^{
    OSStatus status = deleteSigningKeyItem(keyID);
    [self endPrompt];
    if (status == errSecSuccess) {
      callback([BiometricModule deleteJSONForCode:@"success"
                                          message:@""
                                            keyID:keyID]);
    } else if (status == errSecItemNotFound) {
      callback([BiometricModule deleteJSONForCode:@"keyNotFound"
                                          message:@"No signing key with this keyId exists"
                                            keyID:keyID]);
    } else {
      callback([BiometricModule deleteJSONForCode:@"unknown"
                                          message:[NSString stringWithFormat:@"Unable to delete signing key (%d)",
                                                                             (int)status]
                                            keyID:keyID]);
    }
  });
}

- (void)signChallenge:(NSString *)optionsJSON callback:(LynxCallbackBlock)callback {
  NSDictionary<NSString *, id> *options = parseSignOptions(optionsJSON);
  if (options == nil) {
    callback(@"{\"error\":\"Invalid biometric signing options\"}");
    return;
  }
  NSString *keyID = options[@"keyId"];
  if (![self beginPrompt]) {
    callback([BiometricModule signatureJSONForCode:@"busy"
                                           message:@"Another authentication request is already active"
                                             keyID:keyID
                                         signature:nil]);
    return;
  }

  dispatch_async(dispatch_get_main_queue(), ^{
    LAContext *context = [[LAContext alloc] init];
    context.localizedFallbackTitle = @"";
    NSString *cancelButtonText = options[@"cancelButtonText"];
    if ([cancelButtonText isKindOfClass:[NSString class]]) {
      context.localizedCancelTitle = cancelButtonText;
    }
    [context evaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics
             localizedReason:options[@"reason"]
                       reply:^(BOOL success, NSError *_Nullable error) {
                         if (!success) {
                           [self endPrompt];
                           callback([BiometricModule signatureJSONForCode:outcomeForLAError(error)
                                                                  message:error.localizedDescription ?: @""
                                                                    keyID:keyID
                                                                signature:nil]);
                           return;
                         }

                         OSStatus status = errSecSuccess;
                         SecKeyRef privateKey = copySigningKey(keyID, context, &status);
                         if (privateKey == NULL) {
                           [self endPrompt];
                           callback([BiometricModule signatureJSONForCode:@"keyNotFound"
                                                                  message:@"No usable signing key with this keyId exists"
                                                                    keyID:keyID
                                                                signature:nil]);
                           return;
                         }
                         CFErrorRef signError = NULL;
                         CFDataRef derSignature = SecKeyCreateSignature(
                             privateKey, kSecKeyAlgorithmECDSASignatureMessageX962SHA256,
                             (__bridge CFDataRef)options[@"payloadData"], &signError);
                         CFRelease(privateKey);
                         if (derSignature == NULL) {
                           NSString *message = messageForCFError(
                               signError, @"Unable to sign challenge");
                           [self endPrompt];
                           callback([BiometricModule signatureJSONForCode:@"unknown"
                                                                  message:message
                                                                    keyID:keyID
                                                                signature:nil]);
                           return;
                         }
                         NSData *raw = ecdsaDERToRaw(CFBridgingRelease(derSignature));
                         if (raw.length != 64) {
                           [self endPrompt];
                           callback([BiometricModule signatureJSONForCode:@"unknown"
                                                                  message:@"Malformed ECDSA signature"
                                                                    keyID:keyID
                                                                signature:nil]);
                           return;
                         }
                         [self endPrompt];
                         callback([BiometricModule signatureJSONForCode:@"success"
                                                                message:@""
                                                                  keyID:keyID
                                                              signature:[raw base64EncodedStringWithOptions:0]]);
                       }];
  });
}

#pragma mark - Key helpers

static NSData *signingKeyTag(NSString *keyID) {
  return [[kSigningKeyPrefix stringByAppendingString:keyID]
      dataUsingEncoding:NSUTF8StringEncoding];
}

static SecKeyRef copySigningKey(NSString *keyID, LAContext *_Nullable context,
                                OSStatus *statusOut) {
  NSMutableDictionary *query = [@{
    (id)kSecClass : (id)kSecClassKey,
    (id)kSecAttrKeyType : (id)kSecAttrKeyTypeECSECPrimeRandom,
    (id)kSecAttrApplicationTag : signingKeyTag(keyID),
    (id)kSecReturnRef : @YES,
    (id)kSecMatchLimit : (id)kSecMatchLimitOne,
  } mutableCopy];
  if (context != nil) {
    query[(id)kSecUseAuthenticationContext] = context;
  } else {
    LAContext *nonInteractive = [[LAContext alloc] init];
    nonInteractive.interactionNotAllowed = YES;
    query[(id)kSecUseAuthenticationContext] = nonInteractive;
  }
  SecKeyRef privateKey = NULL;
  OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query,
                                        (CFTypeRef *)&privateKey);
  if (statusOut != NULL) *statusOut = status;
  return status == errSecSuccess ? privateKey : NULL;
}

static OSStatus deleteSigningKeyItem(NSString *keyID) {
  NSDictionary *query = @{
    (id)kSecClass : (id)kSecClassKey,
    (id)kSecAttrKeyType : (id)kSecAttrKeyTypeECSECPrimeRandom,
    (id)kSecAttrApplicationTag : signingKeyTag(keyID),
  };
  return SecItemDelete((__bridge CFDictionaryRef)query);
}

static NSData *_Nullable exportPublicPoint(SecKeyRef privateKey) {
  SecKeyRef publicKey = SecKeyCopyPublicKey(privateKey);
  if (publicKey == NULL) return nil;
  CFErrorRef error = NULL;
  CFDataRef point = SecKeyCopyExternalRepresentation(publicKey, &error);
  CFRelease(publicKey);
  if (error != NULL) CFRelease(error);
  return point == NULL ? nil : CFBridgingRelease(point);
}

static NSString *securityLevelForKey(SecKeyRef key) {
  CFDictionaryRef attributesRef = SecKeyCopyAttributes(key);
  if (attributesRef == NULL) return @"unknown";
  NSDictionary *attributes = CFBridgingRelease(attributesRef);
  id tokenID = attributes[(id)kSecAttrTokenID];
  if ([tokenID isEqual:(id)kSecAttrTokenIDSecureEnclave]) return @"secureHardware";
#if TARGET_OS_SIMULATOR
  return @"software";
#else
  return tokenID == nil ? @"unknown" : @"software";
#endif
}

static NSData *_Nullable ecdsaDERToRaw(NSData *der) {
  const uint8_t *bytes = der.bytes;
  NSUInteger length = der.length;
  if (length < 8 || bytes[0] != 0x30) return nil;
  NSUInteger offset = 1;
  NSUInteger sequenceLength = 0;
  if (!readDERLength(bytes, length, &offset, &sequenceLength) ||
      offset + sequenceLength != length) {
    return nil;
  }
  NSData *r = readDERInteger(bytes, length, &offset);
  NSData *s = readDERInteger(bytes, length, &offset);
  if (r == nil || s == nil || offset != length || r.length > 32 || s.length > 32) {
    return nil;
  }
  NSMutableData *raw = [NSMutableData dataWithLength:64];
  uint8_t *target = raw.mutableBytes;
  memcpy(target + (32 - r.length), r.bytes, r.length);
  memcpy(target + 32 + (32 - s.length), s.bytes, s.length);
  return raw;
}

static BOOL readDERLength(const uint8_t *bytes, NSUInteger total,
                          NSUInteger *offset, NSUInteger *value) {
  if (*offset >= total) return NO;
  uint8_t first = bytes[(*offset)++];
  if ((first & 0x80) == 0) {
    *value = first;
    return YES;
  }
  NSUInteger count = first & 0x7f;
  if (count == 0 || count > sizeof(NSUInteger) || *offset + count > total) return NO;
  NSUInteger result = 0;
  for (NSUInteger index = 0; index < count; index++) {
    result = (result << 8) | bytes[(*offset)++];
  }
  *value = result;
  return YES;
}

static NSData *_Nullable readDERInteger(const uint8_t *bytes, NSUInteger total,
                                        NSUInteger *offset) {
  if (*offset >= total || bytes[(*offset)++] != 0x02) return nil;
  NSUInteger length = 0;
  if (!readDERLength(bytes, total, offset, &length) ||
      length == 0 || *offset + length > total) {
    return nil;
  }
  NSUInteger start = *offset;
  *offset += length;
  while (length > 0 && bytes[start] == 0x00) {
    start++;
    length--;
  }
  return [NSData dataWithBytes:bytes + start length:length];
}

#pragma mark - Parsing and support

static NSDictionary<NSString *, id> *_Nullable parseJSONObject(NSString *json) {
  if (![json isKindOfClass:[NSString class]]) return nil;
  NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
  if (data == nil) return nil;
  id value = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
  return [value isKindOfClass:[NSDictionary class]] ? value : nil;
}

static NSString *_Nullable normalizedText(id value, NSUInteger maximum,
                                           BOOL required) {
  if (![value isKindOfClass:[NSString class]]) return required ? nil : nil;
  NSString *text = [value stringByTrimmingCharactersInSet:
                              NSCharacterSet.whitespaceAndNewlineCharacterSet];
  if (text.length == 0) return required ? nil : nil;
  return text.length <= maximum ? text : nil;
}

static NSString *_Nullable policyFromOptions(NSDictionary<NSString *, id> *options) {
  NSString *policy = options[@"policy"];
  if (policy == nil) return kPolicyWeak;
  if ([policy isEqualToString:kPolicyWeak] || [policy isEqualToString:kPolicyStrong] ||
      [policy isEqualToString:kPolicyDeviceOwner]) {
    return policy;
  }
  return nil;
}

static BOOL matchesPattern(NSString *value, NSString *pattern) {
  NSRange range = [value rangeOfString:pattern options:NSRegularExpressionSearch];
  return range.location == 0 && range.length == value.length;
}

static BOOL validScope(NSString *scope) {
  return [scope isKindOfClass:[NSString class]] &&
         matchesPattern(scope, @"^[A-Za-z0-9._-]{1,64}$");
}

static BOOL validKeyID(NSString *keyID) {
  return [keyID isKindOfClass:[NSString class]] &&
         matchesPattern(keyID,
                        @"^[A-Za-z0-9._-]{1,64}~[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$");
}

static NSString *_Nullable scopeFromKeyID(NSString *keyID) {
  if (!validKeyID(keyID)) return nil;
  return [keyID substringToIndex:[keyID rangeOfString:@"~"
                                                    options:NSBackwardsSearch].location];
}

static NSData *_Nullable canonicalBase64(id value, NSUInteger minimum,
                                          NSUInteger maximum) {
  if (![value isKindOfClass:[NSString class]] || [value length] == 0 ||
      [value length] % 4 != 0) {
    return nil;
  }
  NSData *decoded = [[NSData alloc] initWithBase64EncodedString:value options:0];
  if (decoded == nil || decoded.length < minimum || decoded.length > maximum) return nil;
  return [[decoded base64EncodedStringWithOptions:0] isEqualToString:value]
             ? decoded
             : nil;
}

static BOOL validSigningPayload(NSData *payload, NSString *keyID) {
  NSData *domain = [kSigningDomain dataUsingEncoding:NSASCIIStringEncoding];
  NSData *key = [keyID dataUsingEncoding:NSASCIIStringEncoding];
  NSUInteger headerLength = domain.length + 1 + key.length + 1;
  if (payload.length < headerLength + 32 + 16 ||
      payload.length > headerLength + 32 + 64) {
    return NO;
  }
  const uint8_t *bytes = payload.bytes;
  if (memcmp(bytes, domain.bytes, domain.length) != 0 || bytes[domain.length] != 0) {
    return NO;
  }
  NSUInteger keyOffset = domain.length + 1;
  return memcmp(bytes + keyOffset, key.bytes, key.length) == 0 &&
         bytes[keyOffset + key.length] == 0;
}

static NSDictionary<NSString *, id> *_Nullable parsePromptOptions(
    NSString *json, BOOL includePolicy) {
  NSDictionary<NSString *, id> *parsed = parseJSONObject(json);
  NSString *title = normalizedText(parsed[@"title"], 200, YES);
  NSString *reason = normalizedText(parsed[@"reason"], 500, YES);
  NSString *policy = includePolicy ? policyFromOptions(parsed) : kPolicyStrong;
  if (parsed == nil || title == nil || reason == nil || policy == nil) return nil;
  NSMutableDictionary<NSString *, id> *result = [@{
    @"title" : title,
    @"reason" : reason,
    @"policy" : policy,
  } mutableCopy];
  id rawSubtitle = parsed[@"subtitle"];
  if (rawSubtitle != nil) {
    NSString *subtitle = normalizedText(rawSubtitle, 200, NO);
    if (subtitle == nil) return nil;
    result[@"subtitle"] = subtitle;
  }
  id rawCancel = parsed[@"cancelButtonText"];
  if (rawCancel != nil) {
    NSString *cancel = normalizedText(rawCancel, 60, NO);
    if (cancel == nil) return nil;
    result[@"cancelButtonText"] = cancel;
  }
  return result;
}

static NSDictionary<NSString *, id> *_Nullable parseKeyCreateOptions(NSString *json) {
  NSDictionary<NSString *, id> *parsed = parseJSONObject(json);
  NSString *scope = [parsed[@"scope"] isKindOfClass:[NSString class]]
                        ? [parsed[@"scope"] stringByTrimmingCharactersInSet:
                                                   NSCharacterSet.whitespaceAndNewlineCharacterSet]
                        : nil;
  if (parsed == nil || !validScope(scope)) return nil;
  id challenge = parsed[@"attestationChallenge"];
  if (challenge != nil && canonicalBase64(challenge, 16, 128) == nil) return nil;
  return challenge == nil ? @{ @"scope" : scope }
                          : @{ @"scope" : scope, @"attestationChallenge" : challenge };
}

static NSString *_Nullable keyIDFromOptions(NSString *json) {
  NSDictionary<NSString *, id> *parsed = parseJSONObject(json);
  NSString *keyID = [parsed[@"keyId"] isKindOfClass:[NSString class]]
                        ? [parsed[@"keyId"] stringByTrimmingCharactersInSet:
                                                   NSCharacterSet.whitespaceAndNewlineCharacterSet]
                        : nil;
  return validKeyID(keyID) ? keyID : nil;
}

static NSDictionary<NSString *, id> *_Nullable parseSignOptions(NSString *json) {
  NSDictionary<NSString *, id> *prompt = parsePromptOptions(json, NO);
  NSDictionary<NSString *, id> *parsed = parseJSONObject(json);
  NSString *keyID = keyIDFromOptions(json);
  NSData *payload = canonicalBase64(parsed[@"payload"], 1, 256);
  if (prompt == nil || keyID == nil || payload == nil ||
      !validSigningPayload(payload, keyID)) {
    return nil;
  }
  NSMutableDictionary<NSString *, id> *result = [prompt mutableCopy];
  result[@"keyId"] = keyID;
  result[@"payloadData"] = payload;
  return result;
}

- (NSString *)supportJSONForPolicy:(NSString *)policy {
  LAPolicy laPolicy = [policy isEqualToString:kPolicyDeviceOwner]
                          ? LAPolicyDeviceOwnerAuthentication
                          : LAPolicyDeviceOwnerAuthenticationWithBiometrics;
  LAContext *context = [[LAContext alloc] init];
  NSError *error = nil;
  BOOL canAuthenticate = [context canEvaluatePolicy:laPolicy error:&error];

  LAContext *biometryContext = [[LAContext alloc] init];
  [biometryContext canEvaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics
                               error:nil];
  NSString *biometryType = @"unknown";
  if (biometryContext.biometryType == LABiometryTypeFaceID) biometryType = @"face";
  if (biometryContext.biometryType == LABiometryTypeTouchID) biometryType = @"fingerprint";

  LAContext *passcodeContext = [[LAContext alloc] init];
  BOOL deviceCredentialSetup =
      [passcodeContext canEvaluatePolicy:LAPolicyDeviceOwnerAuthentication error:nil];
  NSDictionary *value = @{
    @"policy" : policy,
    @"canAuthenticate" : @(canAuthenticate),
    @"reason" : canAuthenticate ? @"ok" : reasonForLAError(error, @"unknown"),
    @"biometryType" : biometryType,
    @"deviceCredentialSetup" : @(deviceCredentialSetup),
  };
  return JSONEnvelope(value);
}

#pragma mark - Result encoding and errors

static NSString *JSONEnvelope(NSDictionary<NSString *, id> *value) {
  NSData *data = [NSJSONSerialization dataWithJSONObject:@{ @"value" : value }
                                                 options:0
                                                   error:nil];
  return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]
              : @"{\"error\":\"Biometric serialization failed\"}";
}

+ (NSString *)outcomeJSONForCode:(NSString *)code
                         message:(NSString *)message
                          policy:(NSString *)policy {
  return JSONEnvelope(@{
    @"code" : code,
    @"message" : message ?: @"",
    @"policy" : policy,
  });
}

+ (NSString *)keyJSONForCode:(NSString *)code
                     message:(NSString *)message
                       keyID:(nullable NSString *)keyID
                       scope:(nullable NSString *)scope
                   publicKey:(nullable NSString *)publicKey
               securityLevel:(NSString *)securityLevel {
  NSMutableDictionary<NSString *, id> *value = [@{
    @"code" : code,
    @"message" : message ?: @"",
    @"securityLevel" : securityLevel,
    @"attestationType" : @"none",
    @"attestationCertificates" : @[],
  } mutableCopy];
  if (keyID != nil) value[@"keyId"] = keyID;
  if (scope != nil) value[@"scope"] = scope;
  if (publicKey != nil) value[@"publicKey"] = publicKey;
  return JSONEnvelope(value);
}

+ (NSString *)deleteJSONForCode:(NSString *)code
                        message:(NSString *)message
                          keyID:(NSString *)keyID {
  return JSONEnvelope(@{
    @"code" : code,
    @"message" : message ?: @"",
    @"keyId" : keyID,
  });
}

+ (NSString *)signatureJSONForCode:(NSString *)code
                           message:(NSString *)message
                             keyID:(NSString *)keyID
                         signature:(nullable NSString *)signature {
  NSMutableDictionary<NSString *, id> *value = [@{
    @"code" : code,
    @"message" : message ?: @"",
    @"keyId" : keyID,
  } mutableCopy];
  if (signature != nil) value[@"signature"] = signature;
  return JSONEnvelope(value);
}

static NSString *reasonForLAError(NSError *_Nullable error, NSString *fallback) {
  if (error == nil) return fallback;
  switch (error.code) {
    case LAErrorBiometryNotEnrolled:
      return @"notEnrolled";
    case LAErrorBiometryLockout:
      return @"locked";
    case LAErrorBiometryNotAvailable:
      return @"noHardware";
    case LAErrorPasscodeNotSet:
      return @"noDeviceCredential";
    default:
      return fallback;
  }
}

static NSString *outcomeForLAError(NSError *_Nullable error) {
  if (error == nil) return @"unknown";
  switch (error.code) {
    case LAErrorUserCancel:
      return @"userCancel";
    case LAErrorUserFallback:
      return @"userFallback";
    case LAErrorSystemCancel:
      return @"systemCancel";
    case LAErrorAppCancel:
      return @"appCancel";
    case LAErrorAuthenticationFailed:
      return @"failed";
    case LAErrorPasscodeNotSet:
      return @"noDeviceCredential";
    case LAErrorBiometryNotEnrolled:
      return @"notEnrolled";
    case LAErrorBiometryLockout:
      return @"locked";
    case LAErrorBiometryNotAvailable:
      return @"noHardware";
    default:
      return @"unknown";
  }
}

static NSString *messageForCFError(CFErrorRef _Nullable error,
                                   NSString *fallback) {
  if (error == NULL) return fallback;
  NSError *nativeError = CFBridgingRelease(error);
  return nativeError.localizedDescription.length > 0
             ? nativeError.localizedDescription
             : fallback;
}

@end
