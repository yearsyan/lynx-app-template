#import "WebSocketModule.h"

#import <Lynx/LynxContext.h>

static NSString *const kEventName = @"webSocket";

@interface NativeWebSocketConnection : NSObject

@property (nonatomic, copy, readonly) NSString *identifier;
@property (nonatomic, strong, readonly) NSURLSessionWebSocketTask *task;
@property (atomic) BOOL closing;
@property (atomic) NSInteger requestedCloseCode;
@property (nonatomic, copy) NSString *requestedCloseReason;

- (instancetype)initWithIdentifier:(NSString *)identifier
                              task:(NSURLSessionWebSocketTask *)task;

@end

@implementation NativeWebSocketConnection

- (instancetype)initWithIdentifier:(NSString *)identifier
                              task:(NSURLSessionWebSocketTask *)task {
  self = [super init];
  if (self) {
    _identifier = [identifier copy];
    _task = task;
  }
  return self;
}

@end

@interface WebSocketModule () <NSURLSessionWebSocketDelegate>
@end

// The @LynxNativeModule annotation is what cocoapods-lynx-library scans for;
// it expands to a harmless ObjC forward declaration when compiled.
// Exported to Lynx as `WebSocket`.
@LynxNativeModule("WebSocket")
@implementation WebSocketModule {
  LynxContext *_context;
  NSLock *_lock;
  NSMutableDictionary<NSString *, NativeWebSocketConnection *> *_connectionsByID;
  NSMutableDictionary<NSNumber *, NativeWebSocketConnection *> *_connectionsByTaskID;
  BOOL _destroyed;
  BOOL _sessionWasUsed;
  NSURLSession *_session;
}

+ (NSString *)name {
  return @"WebSocket";
}

+ (NSDictionary<NSString *, NSString *> *)methodLookup {
  return @{
    @"connect" : NSStringFromSelector(@selector(connect:callback:)),
    @"sendText" : NSStringFromSelector(@selector(sendText:data:callback:)),
    @"sendBase64" : NSStringFromSelector(@selector(sendBase64:data:callback:)),
    @"close" : NSStringFromSelector(@selector(close:code:reason:callback:)),
  };
}

- (instancetype)initWithLynxContext:(LynxContext *)context {
  self = [super init];
  if (self) {
    _context = context;
    _lock = [[NSLock alloc] init];
    _connectionsByID = [[NSMutableDictionary alloc] init];
    _connectionsByTaskID = [[NSMutableDictionary alloc] init];
  }
  return self;
}

- (void)destroy {
  [_lock lock];
  _destroyed = YES;
  NSArray<NativeWebSocketConnection *> *connections = [_connectionsByID allValues];
  [_connectionsByID removeAllObjects];
  [_connectionsByTaskID removeAllObjects];
  BOOL sessionWasUsed = _sessionWasUsed;
  NSURLSession *session = _session;
  [_lock unlock];

  for (NativeWebSocketConnection *connection in connections) {
    [connection.task cancel];
  }
  if (sessionWasUsed) {
    [session invalidateAndCancel];
  }
}

#pragma mark - Module methods

- (void)connect:(NSDictionary *)options callback:(LynxCallbackBlock)callback {
  NSString *identifier = [options[@"id"] isKindOfClass:[NSString class]] ? options[@"id"] : @"";
  NSString *url = [options[@"url"] isKindOfClass:[NSString class]] ? options[@"url"] : @"";
  NSMutableArray<NSString *> *protocols = [NSMutableArray array];
  for (id protocol in (options[@"protocols"] ?: @[])) {
    if ([protocol isKindOfClass:[NSString class]]) {
      [protocols addObject:protocol];
    }
  }
  NSMutableDictionary<NSString *, NSString *> *headers = [NSMutableDictionary dictionary];
  for (NSString *name in (options[@"headers"] ?: @{})) {
    id value = options[@"headers"][name];
    if ([value isKindOfClass:[NSString class]]) {
      headers[name] = value;
    }
  }
  callback([self connectWithIdentifier:identifier
                                   url:url
                            protocols:protocols
                               headers:headers]);
}

- (void)sendText:(NSString *)identifier
            data:(NSString *)data
        callback:(LynxCallbackBlock)callback {
  NSURLSessionWebSocketMessage *message =
      [[NSURLSessionWebSocketMessage alloc] initWithString:data];
  [self sendWithIdentifier:identifier message:message completion:callback];
}

- (void)sendBase64:(NSString *)identifier
              data:(NSString *)data
          callback:(LynxCallbackBlock)callback {
  NSData *decoded = [[NSData alloc] initWithBase64EncodedString:data options:0];
  if (decoded == nil) {
    callback(@"Invalid Base64 WebSocket payload");
    return;
  }
  NSURLSessionWebSocketMessage *message =
      [[NSURLSessionWebSocketMessage alloc] initWithData:decoded];
  [self sendWithIdentifier:identifier message:message completion:callback];
}

- (void)close:(NSString *)identifier
         code:(NSInteger)code
       reason:(NSString *)reason
     callback:(LynxCallbackBlock)callback {
  NativeWebSocketConnection *connection = [self connectionForIdentifier:identifier];
  if (connection == nil) {
    callback(@"Unknown WebSocket connection ID");
    return;
  }
  if (code < 1000 || (code > 1011 && code < 3000) || code > 4999) {
    callback(@"Invalid WebSocket close code");
    return;
  }
  connection.closing = YES;
  connection.requestedCloseCode = code;
  connection.requestedCloseReason = reason ?: @"";
  [connection.task cancelWithCloseCode:(NSURLSessionWebSocketCloseCode)code
                                reason:[reason dataUsingEncoding:NSUTF8StringEncoding]];
  callback(@"");
}

#pragma mark - URLSession delegate

- (void)URLSession:(NSURLSession *)session
     webSocketTask:(NSURLSessionWebSocketTask *)webSocketTask
didOpenWithProtocol:(NSString *)protocol {
  NativeWebSocketConnection *connection = [self connectionForTaskID:webSocketTask.taskIdentifier];
  if (connection == nil) {
    return;
  }
  [self emitEventWithIdentifier:connection.identifier
                        payload:@{
                          @"type" : @"open",
                          @"protocol" : protocol ?: @"",
                        }];
}

- (void)URLSession:(NSURLSession *)session
     webSocketTask:(NSURLSessionWebSocketTask *)webSocketTask
  didCloseWithCode:(NSURLSessionWebSocketCloseCode)closeCode
            reason:(NSData *)reason {
  NativeWebSocketConnection *connection = [self takeConnectionForTaskID:webSocketTask.taskIdentifier];
  if (connection == nil) {
    return;
  }
  NSString *reasonText = reason.length > 0
      ? [[NSString alloc] initWithData:reason encoding:NSUTF8StringEncoding]
      : nil;
  [self emitEventWithIdentifier:connection.identifier
                        payload:@{
                          @"type" : @"close",
                          @"code" : @(closeCode),
                          @"reason" : reasonText ?: @"",
                          @"wasClean" : @YES,
                        }];
}

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error {
  if (error == nil) {
    return;
  }
  NativeWebSocketConnection *connection = [self connectionForTaskID:task.taskIdentifier];
  if (connection == nil) {
    return;
  }
  if (connection.closing && [error.domain isEqualToString:NSURLErrorDomain]
      && error.code == NSURLErrorCancelled) {
    if ([self takeConnectionForTaskID:task.taskIdentifier] != nil) {
      [self emitEventWithIdentifier:connection.identifier
                            payload:@{
                              @"type" : @"close",
                              @"code" : @(connection.requestedCloseCode),
                              @"reason" : connection.requestedCloseReason,
                              @"wasClean" : @YES,
                            }];
    }
    return;
  }
  if ([self takeConnectionForTaskID:task.taskIdentifier] == nil) {
    return;
  }
  [self emitFailureWithIdentifier:connection.identifier message:error.localizedDescription];
}

#pragma mark - Transport

- (NSString *)connectWithIdentifier:(NSString *)identifier
                               url:(NSString *)url
                        protocols:(NSArray<NSString *> *)protocols
                           headers:(NSDictionary<NSString *, NSString *> *)headers {
  static NSRegularExpression *identifierPattern;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    identifierPattern =
        [NSRegularExpression regularExpressionWithPattern:@"^[A-Za-z0-9._-]{1,128}$" options:0 error:nil];
  });
  NSRange fullRange = NSMakeRange(0, identifier.length);
  if (identifier.length == 0
      || [identifierPattern numberOfMatchesInString:identifier options:0 range:fullRange] == 0) {
    return @"Invalid WebSocket connection ID";
  }
  if (![self isAllowedURL:url]) {
    return @"WebSocket URL must use wss:// (ws:// is Debug-only)";
  }

  [_lock lock];
  BOOL canConnect = !_destroyed && _connectionsByID[identifier] == nil;
  [_lock unlock];
  if (!canConnect) {
    return _destroyed
        ? @"WebSocket host has been destroyed"
        : @"WebSocket connection ID already exists";
  }

  NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
  for (NSString *name in headers) {
    [request setValue:headers[name] forHTTPHeaderField:name];
  }
  if (protocols.count > 0) {
    [request setValue:[protocols componentsJoinedByString:@", "]
        forHTTPHeaderField:@"Sec-WebSocket-Protocol"];
  }

  [_lock lock];
  NSURLSessionWebSocketTask *task = [[self session] webSocketTaskWithRequest:request];
  NativeWebSocketConnection *connection =
      [[NativeWebSocketConnection alloc] initWithIdentifier:identifier task:task];
  if (_destroyed || _connectionsByID[identifier] != nil) {
    [_lock unlock];
    [task cancel];
    return _destroyed
        ? @"WebSocket host has been destroyed"
        : @"WebSocket connection ID already exists";
  }
  _sessionWasUsed = YES;
  _connectionsByID[identifier] = connection;
  _connectionsByTaskID[@(task.taskIdentifier)] = connection;
  [_lock unlock];

  [task resume];
  [self receiveNext:connection];
  return @"";
}

- (void)sendWithIdentifier:(NSString *)identifier
                   message:(NSURLSessionWebSocketMessage *)message
                completion:(LynxCallbackBlock)callback {
  NativeWebSocketConnection *connection = [self connectionForIdentifier:identifier];
  if (connection == nil) {
    callback(@"Unknown WebSocket connection ID");
    return;
  }
  [connection.task sendMessage:message
      completionHandler:^(NSError * _Nullable error) {
        callback(error.localizedDescription ?: @"");
      }];
}

- (void)receiveNext:(NativeWebSocketConnection *)connection {
  __weak WebSocketModule *weakSelf = self;
  [connection.task receiveMessageWithCompletionHandler:^(NSURLSessionWebSocketMessage * _Nullable message,
                                                          NSError * _Nullable error) {
    WebSocketModule *strongSelf = weakSelf;
    if (strongSelf == nil) {
      return;
    }
    if ([strongSelf connectionForIdentifier:connection.identifier] != connection) {
      return;
    }
    if (error != nil) {
      if (connection.closing) {
        return;
      }
      if ([strongSelf takeConnectionForIdentifier:connection.identifier] != nil) {
        [strongSelf emitFailureWithIdentifier:connection.identifier
                                       message:error.localizedDescription];
      }
      return;
    }
    if (message.type == NSURLSessionWebSocketMessageTypeString) {
      [strongSelf emitEventWithIdentifier:connection.identifier
                                  payload:@{
                                    @"type" : @"message",
                                    @"dataType" : @"text",
                                    @"data" : message.string ?: @"",
                                  }];
    } else if (message.type == NSURLSessionWebSocketMessageTypeData) {
      [strongSelf emitEventWithIdentifier:connection.identifier
                                  payload:@{
                                    @"type" : @"message",
                                    @"dataType" : @"base64",
                                    @"data" : [message.data base64EncodedStringWithOptions:0],
                                  }];
    } else {
      [strongSelf emitFailureWithIdentifier:connection.identifier
                                    message:@"Unsupported WebSocket message type"];
      return;
    }
    [strongSelf receiveNext:connection];
  }];
}

#pragma mark - Helpers

- (NSURLSession *)session {
  if (_session == nil) {
    _session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]
                                              delegate:self
                                         delegateQueue:nil];
  }
  return _session;
}

- (NativeWebSocketConnection *)connectionForIdentifier:(NSString *)identifier {
  [_lock lock];
  NativeWebSocketConnection *connection = _destroyed ? nil : _connectionsByID[identifier];
  [_lock unlock];
  return connection;
}

- (NativeWebSocketConnection *)connectionForTaskID:(NSUInteger)taskID {
  [_lock lock];
  NativeWebSocketConnection *connection = _destroyed ? nil : _connectionsByTaskID[@(taskID)];
  [_lock unlock];
  return connection;
}

- (NativeWebSocketConnection *)takeConnectionForIdentifier:(NSString *)identifier {
  [_lock lock];
  NativeWebSocketConnection *connection = _connectionsByID[identifier];
  if (_destroyed || connection == nil) {
    [_lock unlock];
    return nil;
  }
  [_connectionsByID removeObjectForKey:identifier];
  [_connectionsByTaskID removeObjectForKey:@(connection.task.taskIdentifier)];
  [_lock unlock];
  return connection;
}

- (NativeWebSocketConnection *)takeConnectionForTaskID:(NSUInteger)taskID {
  [_lock lock];
  NativeWebSocketConnection *connection = _connectionsByTaskID[@(taskID)];
  if (_destroyed || connection == nil) {
    [_lock unlock];
    return nil;
  }
  [_connectionsByTaskID removeObjectForKey:@(taskID)];
  [_connectionsByID removeObjectForKey:connection.identifier];
  [_lock unlock];
  return connection;
}

- (void)emitFailureWithIdentifier:(NSString *)identifier message:(NSString *)message {
  [self emitEventWithIdentifier:identifier
                        payload:@{
                          @"type" : @"error",
                          @"message" : message,
                        }];
  [self emitEventWithIdentifier:identifier
                        payload:@{
                          @"type" : @"close",
                          @"code" : @1006,
                          @"reason" : message,
                          @"wasClean" : @NO,
                        }];
}

- (void)emitEventWithIdentifier:(NSString *)identifier payload:(NSDictionary *)payload {
  [_lock lock];
  BOOL canEmit = !_destroyed;
  [_lock unlock];
  if (!canEmit) {
    return;
  }
  NSMutableDictionary *event = [payload mutableCopy];
  event[@"id"] = identifier;
  LynxContext *context = _context;
  dispatch_async(dispatch_get_main_queue(), ^{
    [context sendGlobalEvent:kEventName withParams:@[event]];
  });
}

- (BOOL)isAllowedURL:(NSString *)value {
  NSURL *url = [NSURL URLWithString:value];
  if (url == nil || url.host.length == 0) {
    return NO;
  }
  NSString *scheme = url.scheme.lowercaseString;
  if ([scheme isEqualToString:@"wss"]) {
    return YES;
  }
#if DEBUG
  return [scheme isEqualToString:@"ws"];
#else
  return NO;
#endif
}

@end
