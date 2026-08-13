// Copyright 2024 The Lynx Authors. All rights reserved.
// Licensed under the Apache License Version 2.0 that can be found in the
// LICENSES/Apache-2.0.txt file in the root directory of this repository.
// Modified by the Lynx template project to provide app-owned transport hooks.

#import <Foundation/Foundation.h>
#import <Lynx/LynxService.h>
#import <Lynx/LynxServiceHttpProtocol.h>

static const NSInteger LynxTemplateHTTPErrorStatusCode = 499;
static NSString *const LynxTemplateDeprecatedStreamingFlag = @"useStreaming";

@interface LynxTemplateHTTPStreamReceiver : NSObject <NSURLSessionDataDelegate>

- (instancetype)initWithDelegate:(LynxHttpStreamingDelegate *)delegate
                         callback:(LynxHttpCallback)callback
          useDeprecatedStreaming:(BOOL)useDeprecatedStreaming;

@end

@interface LynxTemplateHttpService : NSObject <LynxServiceHttpProtocol>

@property(atomic, strong, nullable) id<LynxHttpInterceptor> interceptor;

@end

@implementation LynxTemplateHTTPStreamReceiver {
  LynxHttpStreamingDelegate *_lynxDelegate;
  LynxHttpCallback _callback;
  NSMutableData *_buffer;
  BOOL _useDeprecatedStreaming;
  BOOL _useServerSentEvents;
}

- (instancetype)initWithDelegate:(LynxHttpStreamingDelegate *)delegate
                         callback:(LynxHttpCallback)callback
          useDeprecatedStreaming:(BOOL)useDeprecatedStreaming {
  self = [super init];
  if (self) {
    _lynxDelegate = delegate;
    _callback = [callback copy];
    _buffer = [[NSMutableData alloc] init];
    _useDeprecatedStreaming = useDeprecatedStreaming;
  }
  return self;
}

- (void)URLSession:(NSURLSession *)session
              dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveResponse:(NSURLResponse *)response
     completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler {
  LynxHttpResponse *lynxResponse = [[LynxHttpResponse alloc] init];
  lynxResponse.url = response.URL.absoluteString;

  if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
    lynxResponse.statusCode = httpResponse.statusCode;
    lynxResponse.statusText = [NSHTTPURLResponse localizedStringForStatusCode:httpResponse.statusCode];
    lynxResponse.httpHeaders = httpResponse.allHeaderFields;

    for (id key in httpResponse.allHeaderFields) {
      if ([[key description] caseInsensitiveCompare:@"Content-Type"] == NSOrderedSame) {
        NSString *value = [httpResponse.allHeaderFields[key] description];
        _useServerSentEvents =
            [value rangeOfString:@"text/event-stream" options:NSCaseInsensitiveSearch].location !=
            NSNotFound;
        break;
      }
    }
  } else {
    lynxResponse.statusCode = LynxTemplateHTTPErrorStatusCode;
    lynxResponse.statusText = @"Response was not HTTP";
  }

  _callback(lynxResponse);
  completionHandler(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveData:(NSData *)data {
  if (_useDeprecatedStreaming) {
    [_lynxDelegate processChunkedData:_buffer withData:data];
  } else if (_useServerSentEvents) {
    [_lynxDelegate processSseData:_buffer withData:data];
  } else {
    [_lynxDelegate processStreamingData:data];
  }
}

- (void)URLSession:(NSURLSession *)session
                    task:(NSURLSessionTask *)task
    didCompleteWithError:(NSError *)error {
  if (error) {
    [_lynxDelegate onError:error.localizedDescription];
  }
  [_lynxDelegate onEnd];
  [session finishTasksAndInvalidate];
}

@end

@LynxServiceRegister(LynxTemplateHttpService, LynxServiceHttpProtocol)
@implementation LynxTemplateHttpService

+ (instancetype)sharedInstance {
  static LynxTemplateHttpService *service;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    service = [[LynxTemplateHttpService alloc] init];
  });
  return service;
}

+ (NSMutableURLRequest *)URLRequestFromLynxRequest:(LynxHttpRequest *)request {
  NSURL *URL = [NSURL URLWithString:request.url ?: @""];
  NSString *scheme = URL.scheme.lowercaseString;
  if (!URL || (!([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"]))) {
    return nil;
  }
#if !DEBUG
  if (![scheme isEqualToString:@"https"]) {
    return nil;
  }
#endif

  NSMutableURLRequest *URLRequest = [NSMutableURLRequest requestWithURL:URL];
  URLRequest.HTTPMethod = request.httpMethod.length > 0 ? request.httpMethod.uppercaseString : @"GET";
  for (id key in request.httpHeaders) {
    [URLRequest setValue:[request.httpHeaders[key] description]
      forHTTPHeaderField:[key description]];
  }
  URLRequest.HTTPBody = request.httpBody;
  return URLRequest;
}

+ (LynxHttpResponse *)errorResponseForRequest:(LynxHttpRequest *)request
                                      message:(NSString *)message {
  LynxHttpResponse *response = [[LynxHttpResponse alloc] init];
  response.url = request.url;
  response.statusCode = LynxTemplateHTTPErrorStatusCode;
  response.statusText = message;
  return response;
}

- (nullable LynxHttpResponse *)interceptRequest:(LynxHttpRequest *)request {
  id<LynxHttpInterceptor> interceptor = self.interceptor;
  if (!interceptor) {
    return nil;
  }
  LynxHttpResponse *response = [interceptor interceptRequest:request];
  if (!response) {
    [interceptor onRequest:request];
  }
  return response;
}

- (void)notifyInterceptor:(LynxHttpResponse *)response request:(LynxHttpRequest *)request {
  [self.interceptor onResponse:response withRequest:request];
}

- (void)invokeWithRequest:(LynxHttpRequest *)request callback:(LynxHttpCallback)callback {
  LynxHttpResponse *intercepted = [self interceptRequest:request];
  if (intercepted) {
    callback(intercepted);
    return;
  }

  NSMutableURLRequest *URLRequest = [LynxTemplateHttpService URLRequestFromLynxRequest:request];
  if (!URLRequest) {
    LynxHttpResponse *response =
        [LynxTemplateHttpService errorResponseForRequest:request message:@"Invalid HTTP URL"];
    [self notifyInterceptor:response request:request];
    callback(response);
    return;
  }

  [[[NSURLSession sharedSession]
      dataTaskWithRequest:URLRequest
        completionHandler:^(NSData *_Nullable data, NSURLResponse *_Nullable URLResponse,
                            NSError *_Nullable error) {
          LynxHttpResponse *response = [[LynxHttpResponse alloc] init];
          response.url = URLResponse.URL.absoluteString ?: request.url;
          response.httpBody = data ?: [NSData data];

          if (error) {
            response.statusCode = LynxTemplateHTTPErrorStatusCode;
            response.statusText = error.localizedDescription;
          } else if ([URLResponse isKindOfClass:[NSHTTPURLResponse class]]) {
            NSHTTPURLResponse *HTTPResponse = (NSHTTPURLResponse *)URLResponse;
            response.statusCode = HTTPResponse.statusCode;
            response.statusText =
                [NSHTTPURLResponse localizedStringForStatusCode:HTTPResponse.statusCode];
            response.httpHeaders = HTTPResponse.allHeaderFields;
          } else {
            response.statusCode = LynxTemplateHTTPErrorStatusCode;
            response.statusText = @"Response was not HTTP";
          }

          [self notifyInterceptor:response request:request];
          callback(response);
        }] resume];
}

- (void)invokeStreamingWithRequest:(LynxHttpRequest *)request
                          callback:(LynxHttpCallback)callback
                      withDelegate:(LynxHttpStreamingDelegate *)delegate {
  LynxHttpResponse *intercepted = [self interceptRequest:request];
  if (intercepted) {
    callback(intercepted);
    if (intercepted.httpBody.length > 0) {
      [delegate processStreamingData:intercepted.httpBody];
    }
    [delegate onEnd];
    return;
  }

  NSMutableURLRequest *URLRequest = [LynxTemplateHttpService URLRequestFromLynxRequest:request];
  if (!URLRequest) {
    LynxHttpResponse *response =
        [LynxTemplateHttpService errorResponseForRequest:request message:@"Invalid HTTP URL"];
    [self notifyInterceptor:response request:request];
    callback(response);
    [delegate onError:response.statusText];
    [delegate onEnd];
    return;
  }

  id deprecatedStreamingFlag = request.customConfig[LynxTemplateDeprecatedStreamingFlag];
  BOOL useDeprecatedStreaming =
      [deprecatedStreamingFlag respondsToSelector:@selector(boolValue)] &&
      [deprecatedStreamingFlag boolValue];
  LynxTemplateHTTPStreamReceiver *receiver =
      [[LynxTemplateHTTPStreamReceiver alloc] initWithDelegate:delegate
                                                      callback:^(LynxHttpResponse *response) {
                                                        [self notifyInterceptor:response
                                                                       request:request];
                                                        callback(response);
                                                      }
                                       useDeprecatedStreaming:useDeprecatedStreaming];
  NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
  NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration
                                                        delegate:receiver
                                                   delegateQueue:nil];
  [[session dataTaskWithRequest:URLRequest] resume];
}

- (BOOL)setHttpInterceptor:(id<LynxHttpInterceptor>)interceptor {
  self.interceptor = interceptor;
  return YES;
}

@end
