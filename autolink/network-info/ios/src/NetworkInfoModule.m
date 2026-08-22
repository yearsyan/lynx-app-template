#import "NetworkInfoModule.h"

#import <CoreTelephony/CTTelephonyNetworkInfo.h>
#import <Lynx/LynxContext.h>
#import <Network/Network.h>

static NSString *const kEventName = @"networkInfo";

// The @LynxNativeModule annotation is what cocoapods-lynx-library scans for;
// it expands to a harmless ObjC forward declaration when compiled.
// Exported to Lynx as `NetworkInfo`.
//
// Snapshots come from a persistent NWPathMonitor: getInfo answers from the
// latest path (waiting for the first update when the monitor just started),
// and while listening every path update is forwarded as a `networkInfo`
// global event — the same channel Sensors uses, so no callback is held
// beyond a command ack. No permission or usage description is required.
@LynxNativeModule("NetworkInfo")
@implementation NetworkInfoModule {
  LynxContext *_context;
  nw_path_monitor_t _monitor;
  dispatch_queue_t _monitorQueue;
  NSMutableArray<LynxCallbackBlock> *_pendingInfoCallbacks;
  CTTelephonyNetworkInfo *_telephonyInfo;
  NSString *_currentType;
  NSString *_lastEmittedSignature;
  BOOL _currentConnected;
  BOOL _hasCurrentPath;
  BOOL _listening;
  BOOL _destroyed;
}

+ (NSString *)name {
  return @"NetworkInfo";
}

+ (NSDictionary<NSString *, NSString *> *)methodLookup {
  return @{
    @"getInfo" : NSStringFromSelector(@selector(getInfo:)),
    @"start" : NSStringFromSelector(@selector(start:)),
    @"stop" : NSStringFromSelector(@selector(stop:)),
  };
}

- (instancetype)initWithLynxContext:(LynxContext *)context {
  self = [super init];
  if (self) {
    _context = context;
    _currentType = @"unknown";
  }
  return self;
}

- (void)destroy {
  @synchronized(self) {
    _destroyed = YES;
    _listening = NO;
  }
  [self cancelMonitor];
  [self flushPendingCallbacksWithError:@"NetworkInfo host has been destroyed"];
}

#pragma mark - Module methods

- (void)getInfo:(LynxCallbackBlock)callback {
  BOOL ready;
  @synchronized(self) {
    ready = _hasCurrentPath;
  }
  if (ready) {
    callback([self valueString]);
    return;
  }
  // The monitor delivers its first path asynchronously; hold this one-shot
  // callback until then.
  @synchronized(self) {
    if (_destroyed) {
      callback(@"{\"error\":\"NetworkInfo host has been destroyed\"}");
      return;
    }
    if (_pendingInfoCallbacks == nil) {
      _pendingInfoCallbacks = [NSMutableArray array];
    }
    [_pendingInfoCallbacks addObject:[callback copy]];
  }
  [self ensureMonitor];
}

- (void)start:(LynxCallbackBlock)callback {
  @synchronized(self) {
    if (_destroyed) {
      callback(@"NetworkInfo host has been destroyed");
      return;
    }
    if (_listening) {
      callback(@"");
      return;
    }
    _listening = YES;
  }
  [self ensureMonitor];
  // Observers always start with the current state; when the first path is
  // not in yet, acceptPathUpdate emits as soon as it arrives.
  BOOL ready;
  @synchronized(self) {
    ready = _hasCurrentPath;
  }
  if (ready) {
    [self emitCurrentSnapshot];
  }
  callback(@"");
}

- (void)stop:(LynxCallbackBlock)callback {
  @synchronized(self) {
    _listening = NO;
    _lastEmittedSignature = nil;
  }
  callback(@"");
}

#pragma mark - Path monitor

- (void)ensureMonitor {
  @synchronized(self) {
    if (_monitor != nil || _destroyed) {
      return;
    }
    _monitorQueue = dispatch_queue_create(
        "com.lynxapp.autolink.networkinfo.monitor", DISPATCH_QUEUE_SERIAL);
    _monitor = nw_path_monitor_create();
    __weak NetworkInfoModule *weakSelf = self;
    nw_path_monitor_set_update_handler(_monitor, ^(nw_path_t path) {
      [weakSelf acceptPathUpdate:path];
    });
    nw_path_monitor_set_queue(_monitor, _monitorQueue);
    nw_path_monitor_start(_monitor);
  }
}

- (void)cancelMonitor {
  nw_path_monitor_t monitor;
  @synchronized(self) {
    monitor = _monitor;
    _monitor = nil;
    _monitorQueue = nil;
    _hasCurrentPath = NO;
  }
  if (monitor != nil) {
    nw_path_monitor_set_update_handler(monitor, nil);
    nw_path_monitor_cancel(monitor);
  }
}

- (void)acceptPathUpdate:(nw_path_t)path {
  BOOL connected = nw_path_get_status(path) == nw_path_status_satisfied;
  NSString *type = @"unknown";
  if (!connected) {
    type = @"none";
  } else if (nw_path_uses_interface_type(path, nw_interface_type_wifi)) {
    type = @"wifi";
  } else if (nw_path_uses_interface_type(path, nw_interface_type_cellular)) {
    type = @"cellular";
  } else if (nw_path_uses_interface_type(path, nw_interface_type_wired)) {
    type = @"ethernet";
  } else {
    type = @"other";
  }
  NSArray<LynxCallbackBlock> *pending = nil;
  BOOL listening;
  @synchronized(self) {
    if (_destroyed) {
      return;
    }
    _currentConnected = connected;
    _currentType = type;
    _hasCurrentPath = YES;
    listening = _listening;
    if (_pendingInfoCallbacks.count > 0) {
      pending = _pendingInfoCallbacks;
      _pendingInfoCallbacks = nil;
    }
  }
  NSString *value = [self valueString];
  for (LynxCallbackBlock callback in pending) {
    callback(value);
  }
  if (listening) {
    [self emitCurrentSnapshot];
  }
}

#pragma mark - Snapshot

- (NSString *)cellularGeneration {
  NSString *type;
  @synchronized(self) {
    type = _currentType;
  }
  if (![type isEqualToString:@"cellular"]) {
    return nil;
  }
  if (_telephonyInfo == nil) {
    _telephonyInfo = [[CTTelephonyNetworkInfo alloc] init];
  }
  // Deprecated without replacement since iOS 16.4; still functional, and nil
  // on simulators and devices without a modem.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
  NSDictionary<NSString *, NSString *> *technologies =
      _telephonyInfo.serviceCurrentRadioAccessTechnology;
#pragma clang diagnostic pop
  for (NSString *technology in technologies.allValues) {
    NSString *generation = [self generationForTechnology:technology];
    if (generation != nil) {
      return generation;
    }
  }
  return nil;
}

- (NSString *)generationForTechnology:(NSString *)technology {
  if ([technology isEqualToString:CTRadioAccessTechnologyGPRS]
      || [technology isEqualToString:CTRadioAccessTechnologyEdge]
      || [technology isEqualToString:CTRadioAccessTechnologyCDMA1x]) {
    return @"2g";
  }
  if ([technology isEqualToString:CTRadioAccessTechnologyWCDMA]
      || [technology isEqualToString:CTRadioAccessTechnologyHSDPA]
      || [technology isEqualToString:CTRadioAccessTechnologyHSUPA]
      || [technology isEqualToString:CTRadioAccessTechnologyCDMAEVDORev0]
      || [technology isEqualToString:CTRadioAccessTechnologyCDMAEVDORevA]
      || [technology isEqualToString:CTRadioAccessTechnologyCDMAEVDORevB]
      || [technology isEqualToString:CTRadioAccessTechnologyeHRPD]) {
    return @"3g";
  }
  if ([technology isEqualToString:CTRadioAccessTechnologyLTE]) {
    return @"4g";
  }
  if (@available(iOS 14.1, *)) {
    if ([technology isEqualToString:CTRadioAccessTechnologyNR]
        || [technology isEqualToString:CTRadioAccessTechnologyNRNSA]) {
      return @"5g";
    }
  }
  return nil;
}

- (NSString *)valueString {
  NSString *type;
  BOOL connected;
  @synchronized(self) {
    type = _currentType;
    connected = _currentConnected;
  }
  NSString *generation = [self cellularGeneration];
  long long timestamp = (long long)(NSDate.date.timeIntervalSince1970 * 1000);
  if (generation != nil) {
    return [NSString
        stringWithFormat:
            @"{\"value\":{\"connected\":%@,\"type\":\"%@\",\"cellularGeneration\":\"%@\",\"timestamp\":%lld}}",
            connected ? @"true" : @"false", type, generation, timestamp];
  }
  return [NSString
      stringWithFormat:
          @"{\"value\":{\"connected\":%@,\"type\":\"%@\",\"cellularGeneration\":null,\"timestamp\":%lld}}",
          connected ? @"true" : @"false", type, timestamp];
}

- (void)emitCurrentSnapshot {
  NSString *type;
  BOOL connected;
  @synchronized(self) {
    if (_destroyed) {
      return;
    }
    type = _currentType;
    connected = _currentConnected;
  }
  NSString *generation = [self cellularGeneration];
  // Path updates also fire for address and signal changes; observers only
  // care about material transitions.
  NSString *signature = [NSString
      stringWithFormat:@"%@|%@|%@", connected ? @"1" : @"0", type,
                       generation != nil ? generation : @""];
  @synchronized(self) {
    if ([signature isEqualToString:_lastEmittedSignature]) {
      return;
    }
    _lastEmittedSignature = signature;
  }
  NSMutableDictionary *payload = [NSMutableDictionary dictionary];
  payload[@"connected"] = @(connected);
  payload[@"type"] = type;
  payload[@"cellularGeneration"] =
      generation != nil ? generation : (NSString *)NSNull.null;
  payload[@"timestamp"] = @((long long)(NSDate.date.timeIntervalSince1970 * 1000));
  LynxContext *context = _context;
  dispatch_async(dispatch_get_main_queue(), ^{
    @synchronized(self) {
      if (_destroyed) {
        return;
      }
    }
    [context sendGlobalEvent:kEventName withParams:@[payload]];
  });
}

- (void)flushPendingCallbacksWithError:(NSString *)message {
  NSArray<LynxCallbackBlock> *pending = nil;
  @synchronized(self) {
    if (_pendingInfoCallbacks.count > 0) {
      pending = _pendingInfoCallbacks;
      _pendingInfoCallbacks = nil;
    }
  }
  NSString *value = [NSString
      stringWithFormat:@"{\"error\":\"%@\"}", message];
  for (LynxCallbackBlock callback in pending) {
    callback(value);
  }
}

@end
