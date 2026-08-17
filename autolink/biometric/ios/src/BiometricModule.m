#import "BiometricModule.h"

#import <LocalAuthentication/LocalAuthentication.h>
#import <Security/Security.h>

// Used before their implementation, so forward-declare them here.
@interface BiometricModule ()
+ (NSString *)outcomeJSONForCode:(NSString *)code message:(NSString *)message;
+ (NSString *)cryptoJSONForCode:(NSString *)code
                        message:(NSString *)message
                          field:(NSString *)field
                         payload:(nullable NSString *)payload;
@end

// The @LynxNativeModule annotation is what cocoapods-lynx-library scans for;
// it expands to a harmless ObjC forward declaration when compiled.
// Exported to Lynx as `Biometric`.
@LynxNativeModule("Biometric")
@implementation BiometricModule {
  BOOL _promptActive;
}

+ (NSString *)name {
  return @"Biometric";
}

+ (NSDictionary<NSString *, NSString *> *)methodLookup {
  return @{
    @"checkSupport" : NSStringFromSelector(@selector(checkSupport:)),
    @"authenticate" : NSStringFromSelector(@selector(authenticate:callback:)),
    @"createSigningKey" : NSStringFromSelector(@selector(createSigningKey:)),
    @"signChallenge" : NSStringFromSelector(@selector(signChallenge:callback:)),
  };
}

- (void)checkSupport:(LynxCallbackBlock)callback {
  dispatch_async(dispatch_get_main_queue(), ^{
    callback([self supportJSON]);
  });
}

- (void)authenticate:(NSString *)optionsJSON callback:(LynxCallbackBlock)callback {
  NSDictionary<NSString *, id> *options = [self parseOptions:optionsJSON];
  if (options == nil) {
    callback(@"{\"error\":\"Invalid biometric options\"}");
    return;
  }
  if (_promptActive) {
    callback([BiometricModule outcomeJSONForCode:@"busy"
              message:@"Another authentication request is already active"]);
    return;
  }
  _promptActive = YES;

  dispatch_async(dispatch_get_main_queue(), ^{
    LAContext *context = [[LAContext alloc] init];
    BOOL allowDeviceCredential = [options[@"allowDeviceCredential"] boolValue];
    LAPolicy policy = allowDeviceCredential
                          ? LAPolicyDeviceOwnerAuthentication
                          : LAPolicyDeviceOwnerAuthenticationWithBiometrics;
    // An empty fallback title hides the fallback button; a custom one
    // renames it. It only applies to the biometrics-only policy.
    NSString *cancelButtonText = options[@"cancelButtonText"];
    context.localizedFallbackTitle =
        [cancelButtonText isKindOfClass:[NSString class]] ? cancelButtonText : @"";

    __weak BiometricModule *weakSelf = self;
    [context evaluatePolicy:policy
             localizedReason:options[@"reason"]
                     reply:^(
                         BOOL success, NSError *_Nullable error) {
                      BiometricModule *strongSelf = weakSelf;
                      NSString *code = success ? @"success" : outcomeForLAError(error);
                      NSString *message = success ? @"" : error.localizedDescription ?: @"";
                      if (strongSelf) {
                        strongSelf->_promptActive = NO;
                      }
                      callback([BiometricModule outcomeJSONForCode:code message:message]);
                    }];
  });
}

#pragma mark - Server-verifiable signing key

static NSString *const kSigningKeyTag = @"lynx.biometric.signing";

- (void)createSigningKey:(LynxCallbackBlock)callback {
  dispatch_async(dispatch_get_main_queue(), ^{
    LAContext *probe = [[LAContext alloc] init];
    NSError *probeError = nil;
    if (![probe canEvaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics
                            error:&probeError]) {
      callback([BiometricModule cryptoJSONForCode:reasonForLAError(probeError, @"notSupported")
                                          message:@""
                                            field:@"publicKey"
                                           payload:nil]);
      return;
    }
    // createSigningKey replaces any previous key on purpose: the server
    // rebinds to the returned public key anyway.
    [self deleteSigningKey];

    NSData *tag = [kSigningKeyTag dataUsingEncoding:NSUTF8StringEncoding];
    SecAccessControlRef accessControl = SecAccessControlCreateWithFlags(
        kCFAllocatorDefault, kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        kSecAccessControlPrivateKeyUsage | kSecAccessControlBiometryCurrentSet, NULL);
    NSDictionary *privateAttrs = @{
      (id)kSecAttrIsPermanent : @YES,
      (id)kSecAttrApplicationTag : tag,
      (id)kSecAttrAccessControl : (__bridge id)accessControl,
    };
    NSDictionary *attrs = @{
      (id)kSecAttrKeyType : (id)kSecAttrKeyTypeECSECPrimeRandom,
      (id)kSecAttrKeySizeInBits : @256,
      (id)kSecPrivateKeyAttrs : privateAttrs,
      (id)kSecAttrTokenID : (id)kSecAttrTokenIDSecureEnclave,
    };

    CFErrorRef error = NULL;
    SecKeyRef privateKey = SecKeyCreateRandomKey((__bridge CFDictionaryRef)attrs, &error);
    if (privateKey == NULL) {
      if (error != NULL) {
        CFRelease(error);
        error = NULL;
      }
      // No Secure Enclave (e.g. simulator): fall back to a keychain key that
      // is still gated by the biometric access control above.
      NSMutableDictionary *fallback = [attrs mutableCopy];
      [fallback removeObjectForKey:(id)kSecAttrTokenID];
      privateKey = SecKeyCreateRandomKey((__bridge CFDictionaryRef)fallback, &error);
    }
    if (accessControl != NULL) {
      CFRelease(accessControl);
    }
    if (privateKey == NULL) {
      NSString *message = CFBridgingRelease(error) ?: @"";
      callback([BiometricModule cryptoJSONForCode:@"unknown"
                                          message:message
                                            field:@"publicKey"
                                           payload:nil]);
      return;
    }

    SecKeyRef publicKey = SecKeyCopyPublicKey(privateKey);
    NSData *point = nil;
    if (publicKey != NULL) {
      CFDataRef exported = SecKeyCopyExternalRepresentation(publicKey, NULL);
      if (exported != NULL) {
        // X9.63 uncompressed point: 0x04 || X(32) || Y(32).
        point = CFBridgingRelease(exported);
      }
      CFRelease(publicKey);
    }
    CFRelease(privateKey);
    if (point == nil || point.length != 65) {
      callback([BiometricModule cryptoJSONForCode:@"unknown"
                                          message:@"Unable to export the public key"
                                            field:@"publicKey"
                                           payload:nil]);
      return;
    }
    callback([BiometricModule cryptoJSONForCode:@"success"
                                        message:@""
                                          field:@"publicKey"
                                         payload:[point base64EncodedStringWithOptions:0]]);
  });
}

- (void)signChallenge:(NSString *)optionsJSON callback:(LynxCallbackBlock)callback {
  NSDictionary<NSString *, id> *options = [self parseOptions:optionsJSON];
  NSString *challenge = options[@"challenge"];
  NSData *challengeData = nil;
  if ([challenge isKindOfClass:[NSString class]] && challenge.length > 0) {
    challengeData = [[NSData alloc] initWithBase64EncodedString:challenge options:0];
  }
  if (options == nil || challengeData == nil || challengeData.length == 0) {
    callback(@"{\"error\":\"Invalid biometric options\"}");
    return;
  }
  if (_promptActive) {
    callback([BiometricModule cryptoJSONForCode:@"busy"
                                        message:@"Another authentication request is already active"
                                          field:@"signature"
                                         payload:nil]);
    return;
  }
  _promptActive = YES;

  dispatch_async(dispatch_get_main_queue(), ^{
    LAContext *context = [[LAContext alloc] init];
    NSString *cancelButtonText = options[@"cancelButtonText"];
    context.localizedFallbackTitle =
        [cancelButtonText isKindOfClass:[NSString class]] ? cancelButtonText : @"";
    __weak BiometricModule *weakSelf = self;
    [context
        evaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics
        localizedReason:options[@"reason"]
                reply:^(BOOL success, NSError *_Nullable error) {
                  BiometricModule *strongSelf = weakSelf;
                  if (!success) {
                    if (strongSelf) {
                      strongSelf->_promptActive = NO;
                    }
                    callback([BiometricModule
                        cryptoJSONForCode:outcomeForLAError(error)
                                   message:error.localizedDescription ?: @""
                                     field:@"signature"
                                    payload:nil]);
                    return;
                  }

                  // Fetch the key with the authenticated context; keys
                  // invalidated by biometric re-enrollment no longer match.
                  NSDictionary *query = @{
                    (id)kSecClass : (id)kSecClassKey,
                    (id)kSecAttrKeyType : (id)kSecAttrKeyTypeECSECPrimeRandom,
                    (id)kSecAttrApplicationTag :
                        [kSigningKeyTag dataUsingEncoding:NSUTF8StringEncoding],
                    (id)kSecReturnRef : @YES,
                    (id)kSecUseAuthenticationContext : context,
                  };
                  SecKeyRef privateKey = NULL;
                  OSStatus status =
                      SecItemCopyMatching((__bridge CFDictionaryRef)query,
                                          (CFTypeRef *)&privateKey);
                  if (status != errSecSuccess || privateKey == NULL) {
                    if (strongSelf) {
                      strongSelf->_promptActive = NO;
                    }
                    callback([BiometricModule
                        cryptoJSONForCode:@"keyNotFound"
                                   message:@"No usable signing key on this device"
                                     field:@"signature"
                                    payload:nil]);
                    return;
                  }

                  CFErrorRef signError = NULL;
                  // X962 produces the raw 64-byte r || s form directly.
                  CFDataRef signature =
                      SecKeyCreateSignature(privateKey,
                                            kSecKeyAlgorithmECDSASignatureMessageX962SHA256,
                                            (__bridge CFDataRef)challengeData, &signError);
                  CFRelease(privateKey);
                  if (signature == NULL) {
                    NSString *message = CFBridgingRelease(signError) ?: @"";
                    if (strongSelf) {
                      strongSelf->_promptActive = NO;
                    }
                    callback([BiometricModule cryptoJSONForCode:@"unknown"
                                                        message:message
                                                          field:@"signature"
                                                         payload:nil]);
                    return;
                  }
                  NSData *raw = CFBridgingRelease(signature);
                  if (strongSelf) {
                    strongSelf->_promptActive = NO;
                  }
                  callback([BiometricModule
                      cryptoJSONForCode:@"success"
                                 message:@""
                                   field:@"signature"
                                  payload:[raw base64EncodedStringWithOptions:0]]);
                }];
  });
}

- (void)deleteSigningKey {
  NSDictionary *query = @{
    (id)kSecClass : (id)kSecClassKey,
    (id)kSecAttrApplicationTag :
        [kSigningKeyTag dataUsingEncoding:NSUTF8StringEncoding],
  };
  SecItemDelete((__bridge CFDictionaryRef)query);
}

#pragma mark - Support payload

- (NSString *)supportJSON {
  LAContext *context = [[LAContext alloc] init];
  NSError *error = nil;
  // biometryType is only meaningful after a canEvaluatePolicy call.
  BOOL canAuthenticate =
      [context canEvaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics error:&error];
  NSString *reason = canAuthenticate ? @"ok" : reasonForLAError(error, @"unknown");

  NSString *biometryType = @"unknown";
  switch (context.biometryType) {
    case LABiometryTypeFaceID:
      biometryType = @"face";
      break;
    case LABiometryTypeTouchID:
      biometryType = @"fingerprint";
      break;
    default:
      biometryType = @"unknown";
      break;
  }

  LAContext *passcodeContext = [[LAContext alloc] init];
  NSError *passcodeError = nil;
  BOOL deviceCredentialSetup = [passcodeContext canEvaluatePolicy:LAPolicyDeviceOwnerAuthentication
                                                            error:&passcodeError];

  NSDictionary *value = @{
    @"canAuthenticate" : @(canAuthenticate),
    @"reason" : reason,
    @"biometryType" : biometryType,
    @"deviceCredentialSetup" : @(deviceCredentialSetup),
  };
  NSData *data = [NSJSONSerialization dataWithJSONObject:@{ @"value" : value }
                                                 options:0
                                                   error:nil];
  return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]
              : @"{\"error\":\"Biometric serialization failed\"}";
}

- (nullable NSDictionary<NSString *, id> *)parseOptions:(NSString *)optionsJSON {
  NSData *data = [optionsJSON dataUsingEncoding:NSUTF8StringEncoding];
  if (data == nil) {
    return nil;
  }
  NSError *error = nil;
  id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
  if (![parsed isKindOfClass:[NSDictionary class]]) {
    return nil;
  }
  NSDictionary<NSString *, id> *options = parsed;
  NSString *title = options[@"title"];
  NSString *reason = options[@"reason"];
  if (![title isKindOfClass:[NSString class]] || title.length == 0 ||
      ![reason isKindOfClass:[NSString class]] || reason.length == 0) {
    return nil;
  }
  return options;
}

#pragma mark - Mapping helpers

static NSString *reasonForLAError(NSError *_Nullable error, NSString *fallback) {
  if (error == nil) {
    return fallback;
  }
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
  if (error == nil) {
    return @"unknown";
  }
  switch (error.code) {
    case LAErrorUserCancel:
      return @"userCancel";
    case LAErrorUserFallback:
      return @"userFallback";
    case LAErrorSystemCancel:
      return @"systemCancel";
    case LAErrorAppCancel:
      return @"appCancel";
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

+ (NSString *)outcomeJSONForCode:(NSString *)code message:(NSString *)message {
  NSDictionary *value = @{ @"code" : code, @"message" : message ?: @"" };
  NSData *data = [NSJSONSerialization dataWithJSONObject:@{ @"value" : value }
                                                 options:0
                                                   error:nil];
  return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]
              : @"{\"error\":\"Biometric serialization failed\"}";
}

+ (NSString *)cryptoJSONForCode:(NSString *)code
                        message:(NSString *)message
                          field:(NSString *)field
                         payload:(nullable NSString *)payload {
  NSMutableDictionary *value = [NSMutableDictionary dictionaryWithDictionary:@{
    @"code" : code,
    @"message" : message ?: @"",
  }];
  if (payload != nil) {
    value[field] = payload;
  }
  NSData *data = [NSJSONSerialization dataWithJSONObject:@{ @"value" : value }
                                                 options:0
                                                   error:nil];
  return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]
              : @"{\"error\":\"Biometric serialization failed\"}";
}

@end
