// Copyright 2024 The Lynx Authors. All rights reserved.
// Licensed under the Apache License Version 2.0 that can be found in the
// LICENSES/Apache-2.0.txt file in the root directory of this repository.
// Implemented for the Lynx template project to load runtime-requested Lynx
// resources such as rspeedy HMR patches outside the template provider flow.

#import "LynxGenericResourceFetcher.h"

#import <Lynx/LynxResourceRequest.h>

@implementation AppGenericResourceFetcher

- (dispatch_block_t)fetchResource:(LynxResourceRequest *)request
                        onComplete:(LynxGenericResourceCompletionBlock)callback {
  NSURL *url = [NSURL URLWithString:request.url];
  NSString *scheme = url.scheme.lowercaseString;
  BOOL cleartextAllowed = NO;
#if DEBUG
  cleartextAllowed = YES;
#endif
  if (url == nil || scheme.length == 0) {
    callback(nil, [self errorWithMessage:[NSString
        stringWithFormat:@"Invalid resource URL: %@", request.url]]);
    return ^{};
  }
  if (![scheme isEqualToString:@"https"] &&
      (!cleartextAllowed || ![scheme isEqualToString:@"http"])) {
    callback(nil, [self errorWithMessage:[NSString
        stringWithFormat:@"Cleartext HTTP is disabled in release builds: %@",
                         request.url]]);
    return ^{};
  }

  NSURLSessionDataTask *task =
      [[NSURLSession sharedSession] dataTaskWithURL:url
        completionHandler:^(NSData *_Nullable data, NSURLResponse *_Nullable response,
                            NSError *_Nullable error) {
          if (error != nil) {
            callback(nil, error);
            return;
          }
          if (![response isKindOfClass:[NSHTTPURLResponse class]]) {
            callback(nil, [self errorWithMessage:@"Resource response was not HTTP"]);
            return;
          }
          NSInteger status = ((NSHTTPURLResponse *)response).statusCode;
          if (status < 200 || status >= 300) {
            callback(nil, [self errorWithMessage:[NSString
                stringWithFormat:@"HTTP %ld for %@",
                                 (long)status, url.absoluteString]]);
            return;
          }
          callback(data ?: [NSData data], nil);
        }];
  [task resume];
  return ^{ [task cancel]; };
}

- (dispatch_block_t)fetchResourcePath:(LynxResourceRequest *)request
                           onComplete:(LynxGenericResourcePathCompletionBlock)callback {
  callback(nil, [self errorWithMessage:[NSString
      stringWithFormat:@"fetchResourcePath is unsupported for %@", request.url]]);
  return ^{};
}

- (NSError *)errorWithMessage:(NSString *)message {
  return [NSError errorWithDomain:@"com.lynxapp.generic-resource-fetcher"
                             code:-1
                         userInfo:@{NSLocalizedDescriptionKey : message}];
}

@end
