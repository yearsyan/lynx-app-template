#import "AudioPlayerModule.h"

#import <Lynx/LynxContext.h>

static NSString *const kEventName = @"audioPlayer";

// Forward declaration so NativeAudioPlayerHandle can emit through the module
// before the module's implementation section is visible.
@interface AudioPlayerModule ()
- (void)emitEventWithIdentifier:(NSString *)identifier payload:(NSDictionary *)payload;
- (void)deactivateSessionIfNeeded;
@end
static NSString *const kStateLoading = @"loading";
static NSString *const kStatePaused = @"paused";
static NSString *const kStatePlaying = @"playing";
static NSString *const kStateStopped = @"stopped";
static const double kDefaultProgressIntervalMs = 250;

/// One local-file player. All work happens on the main queue.
@interface NativeAudioPlayerHandle : NSObject <AVAudioPlayerDelegate>

@property (nonatomic, copy, readonly) NSString *identifier;
@property (nonatomic, copy, readonly) NSString *usage;
@property (nonatomic, assign, readonly) NSTimeInterval progressIntervalMs;
@property (nonatomic, copy, readonly) NSString *state;
@property (nonatomic, assign, readonly) float userVolume;
@property (nonatomic, assign, readonly) float desiredRate;
@property (nonatomic, strong, readonly) AVAudioPlayer *player;
@property (nonatomic, assign) BOOL pausedByInterruption;
@property (nonatomic, weak) AudioPlayerModule *module;

- (instancetype)initWithIdentifier:(NSString *)identifier
                             usage:(NSString *)usage
                 progressIntervalMs:(NSTimeInterval)progressIntervalMs;

- (BOOL)prepareWithURI:(NSURL *)uri error:(NSString **)error;
- (NSString *)play;
- (NSString *)pause;
- (NSString *)seekToPositionMs:(NSInteger)positionMs;
- (NSString *)stop;
- (NSString *)setRate:(float)rate;
- (NSString *)setVolume:(float)volume;
- (NSString *)propsJSON;
- (void)interruptionBegan;
- (void)interruptionEndedShouldResume:(BOOL)shouldResume;
- (void)teardown;

@end

@implementation NativeAudioPlayerHandle {
  NSString *_identifier;
  NSString *_usage;
  NSTimeInterval _progressIntervalMs;
  NSString *_state;
  float _userVolume;
  float _desiredRate;
  AVAudioPlayer *_player;
  dispatch_source_t _ticker;
  BOOL _tornDown;
}

- (instancetype)initWithIdentifier:(NSString *)identifier
                             usage:(NSString *)usage
                 progressIntervalMs:(NSTimeInterval)progressIntervalMs {
  self = [super init];
  if (self) {
    _identifier = [identifier copy];
    _usage = [usage copy];
    _progressIntervalMs = progressIntervalMs;
    _state = kStateLoading;
    _userVolume = 1.0f;
    _desiredRate = 1.0f;
  }
  return self;
}

- (NSString *)identifier {
  return _identifier;
}

- (NSString *)usage {
  return _usage;
}

- (NSTimeInterval)progressIntervalMs {
  return _progressIntervalMs;
}

- (NSString *)state {
  return _state;
}

- (float)userVolume {
  return _userVolume;
}

- (float)desiredRate {
  return _desiredRate;
}

- (AVAudioPlayer *)player {
  return _player;
}

- (BOOL)prepareWithURI:(NSURL *)uri error:(NSString **)error {
  if (![uri isFileURL]) {
    *error = @"AudioPlayer only supports local file:// sources";
    return NO;
  }
  if (![[NSFileManager defaultManager] isReadableFileAtPath:uri.path]) {
    *error = [NSString stringWithFormat:@"file-not-found: %@", uri.path];
    return NO;
  }
  NSError *loadError = nil;
  AVAudioPlayer *loaded = [[AVAudioPlayer alloc] initWithContentsOfURL:uri error:&loadError];
  if (loaded == nil) {
    NSString *detail = loadError.localizedDescription ?: @"unknown codec error";
    *error = [NSString stringWithFormat:@"unsupported-format: %@", detail];
    return NO;
  }
  _player = loaded;
  _player.delegate = self;
  _player.enableRate = YES;
  _player.volume = _userVolume;
  return YES;
}

- (void)finishPreparingWithAutoPlay:(BOOL)autoPlay {
  if (autoPlay) {
    [self startPlayback];
  } else {
    _state = kStatePaused;
    [self emitState:kStatePaused interruption:nil];
  }
}

- (NSString *)play {
  if (_tornDown) {
    return @"AudioPlayer has been released";
  }
  if ([_state isEqualToString:kStatePlaying]) {
    return @"";
  }
  if ([_state isEqualToString:kStateLoading]) {
    return @"AudioPlayer is still loading";
  }
  _pausedByInterruption = NO;
  [self activateSession];
  [self startPlayback];
  return @"";
}

- (NSString *)pause {
  if (_tornDown) {
    return @"AudioPlayer has been released";
  }
  if ([_state isEqualToString:kStatePaused] || [_state isEqualToString:kStateStopped]) {
    return @"";
  }
  [self stopTicker];
  [_player pause];
  _state = kStatePaused;
  [self emitState:kStatePaused interruption:nil];
  return @"";
}

- (NSString *)seekToPositionMs:(NSInteger)positionMs {
  if (_tornDown) {
    return @"AudioPlayer has been released";
  }
  if ([_state isEqualToString:kStateStopped]) {
    return @"AudioPlayer is not seekable in the stopped state";
  }
  NSTimeInterval clamped =
      MAX(0.0, MIN((double)positionMs / 1000.0, _player.duration));
  _player.currentTime = clamped;
  [self emitState:_state interruption:nil];
  return @"";
}

- (NSString *)stop {
  if (_tornDown) {
    return @"AudioPlayer has been released";
  }
  if ([_state isEqualToString:kStateStopped]) {
    return @"";
  }
  [self stopTicker];
  // -stop also rewinds currentTime to 0, which matches the stopped state.
  [_player stop];
  _state = kStateStopped;
  [self emitState:kStateStopped interruption:nil];
  return @"";
}

- (NSString *)setRate:(float)rate {
  if (_tornDown) {
    return @"AudioPlayer has been released";
  }
  _desiredRate = rate;
  _player.rate = rate;
  return @"";
}

- (NSString *)setVolume:(float)volume {
  if (_tornDown) {
    return @"AudioPlayer has been released";
  }
  _userVolume = volume;
  _player.volume = volume;
  return @"";
}

- (NSString *)propsJSON {
  NSDictionary *props = @{
    @"state" : _state,
    @"positionMs" : @(lround(_player.currentTime * 1000.0)),
    @"durationMs" : @(lround(_player.duration * 1000.0)),
    @"usage" : _usage,
    @"rate" : @(_desiredRate),
    @"volume" : @(_userVolume),
  };
  NSData *data = [NSJSONSerialization dataWithJSONObject:props options:0 error:nil];
  return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]
              : @"{\"error\":\"AudioPlayer serialization failed\"}";
}

#pragma mark - Interruptions

- (void)interruptionBegan {
  if (_tornDown || ![_state isEqualToString:kStatePlaying]) {
    return;
  }
  _pausedByInterruption = YES;
  [self stopTicker];
  [_player pause];
  _state = kStatePaused;
  [self emitState:kStatePaused interruption:@"pause"];
}

- (void)interruptionEndedShouldResume:(BOOL)shouldResume {
  if (_tornDown) {
    return;
  }
  if (shouldResume && _pausedByInterruption) {
    _pausedByInterruption = NO;
    [self activateSession];
    [self startPlaybackWithInterruption:@"resume"];
    return;
  }
  _pausedByInterruption = NO;
}

- (void)teardown {
  if (_tornDown) {
    return;
  }
  _tornDown = YES;
  [self stopTicker];
  _player.delegate = nil;
  [_player stop];
  _player = nil;
}

#pragma mark - AVAudioPlayerDelegate

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag {
  if (_tornDown) {
    return;
  }
  [self stopTicker];
  _state = kStatePaused;
  [self emitState:kStatePaused interruption:nil];
  [self emitEvent:@{ @"type" : @"end" }];
  // Rewind so the next play() restarts instead of sitting at the end.
  _player.currentTime = 0;
  [self.module deactivateSessionIfNeeded];
}

#pragma mark - Playback internals

- (void)startPlayback {
  [self startPlaybackWithInterruption:nil];
}

- (void)startPlaybackWithInterruption:(nullable NSString *)interruption {
  [self activateSession];
  _player.rate = _desiredRate;
  [_player play];
  _state = kStatePlaying;
  [self emitState:kStatePlaying interruption:interruption];
  [self startTicker];
}

- (void)activateSession {
  AVAudioSession *session = [AVAudioSession sharedInstance];
  NSError *error = nil;
  if ([_usage isEqualToString:@"ambient"]) {
    [session setCategory:AVAudioSessionCategoryAmbient error:&error];
  } else {
    [session setCategory:AVAudioSessionCategoryPlayback error:&error];
  }
  if (error == nil) {
    [session setActive:YES error:&error];
  }
}

- (void)startTicker {
  [self stopTicker];
  dispatch_source_t ticker = dispatch_source_create(
      DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
  if (ticker == nil) {
    return;
  }
  dispatch_source_set_timer(
      ticker, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(_progressIntervalMs * NSEC_PER_MSEC)),
      (uint64_t)(_progressIntervalMs * NSEC_PER_MSEC), (uint64_t)(50 * NSEC_PER_MSEC));
  __weak NativeAudioPlayerHandle *weakSelf = self;
  dispatch_source_set_event_handler(ticker, ^{
    NativeAudioPlayerHandle *strongSelf = weakSelf;
    if (strongSelf == nil) {
      return;
    }
    if (![strongSelf->_state isEqualToString:kStatePlaying]) {
      return;
    }
    [strongSelf emitEvent:@{
      @"type" : @"progress",
      @"state" : strongSelf->_state,
      @"positionMs" : @(lround(strongSelf->_player.currentTime * 1000.0)),
      @"durationMs" : @(lround(strongSelf->_player.duration * 1000.0)),
    }];
  });
  dispatch_resume(ticker);
  _ticker = ticker;
}

- (void)stopTicker {
  if (_ticker != nil) {
    dispatch_source_cancel(_ticker);
    _ticker = nil;
  }
}

#pragma mark - Events

- (void)emitState:(NSString *)state interruption:(nullable NSString *)interruption {
  NSMutableDictionary *payload = [@{
    @"type" : @"state",
    @"state" : state,
    @"positionMs" : @(lround(_player.currentTime * 1000.0)),
    @"durationMs" : @(lround(_player.duration * 1000.0)),
  } mutableCopy];
  if (interruption != nil) {
    payload[@"interruption"] = interruption;
  }
  [self emitEvent:payload];
}

- (void)emitEvent:(NSDictionary *)payload {
  AudioPlayerModule *module = self.module;
  if (module == nil) {
    return;
  }
  [module emitEventWithIdentifier:_identifier payload:payload];
}

@end

// The @LynxNativeModule annotation is what cocoapods-lynx-library scans for;
// it expands to a harmless ObjC forward declaration when compiled.
// Exported to Lynx as `AudioPlayer`.
@LynxNativeModule("AudioPlayer")
@implementation AudioPlayerModule {
  LynxContext *_context;
  NSLock *_lock;
  NSMutableDictionary<NSString *, NativeAudioPlayerHandle *> *_playersByID;
  id _interruptionObserver;
  BOOL _destroyed;
}

+ (NSString *)name {
  return @"AudioPlayer";
}

+ (NSDictionary<NSString *, NSString *> *)methodLookup {
  return @{
    @"create" : NSStringFromSelector(@selector(create:callback:)),
    @"play" : NSStringFromSelector(@selector(play:callback:)),
    @"pause" : NSStringFromSelector(@selector(pause:callback:)),
    @"seek" : NSStringFromSelector(@selector(seek:positionMs:callback:)),
    @"stop" : NSStringFromSelector(@selector(stop:callback:)),
    @"release" : NSStringFromSelector(@selector(release:callback:)),
    @"setRate" : NSStringFromSelector(@selector(setRate:rate:callback:)),
    @"setVolume" : NSStringFromSelector(@selector(setVolume:volume:callback:)),
    @"getProps" : NSStringFromSelector(@selector(getProps:callback:)),
  };
}

- (instancetype)initWithLynxContext:(LynxContext *)context {
  self = [super init];
  if (self) {
    _context = context;
    _lock = [[NSLock alloc] init];
    _playersByID = [[NSMutableDictionary alloc] init];
    __weak AudioPlayerModule *weakSelf = self;
    _interruptionObserver = [[NSNotificationCenter defaultCenter]
        addObserverForName:AVAudioSessionInterruptionNotification
                    object:[AVAudioSession sharedInstance]
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *notification) {
                  AudioPlayerModule *strongSelf = weakSelf;
                  if (strongSelf == nil) {
                    return;
                  }
                  NSUInteger typeValue =
                      [notification.userInfo[AVAudioSessionInterruptionTypeKey] unsignedIntegerValue];
                  BOOL shouldResume =
                      [notification.userInfo[AVAudioSessionInterruptionOptionKey] unsignedIntegerValue] ==
                      AVAudioSessionInterruptionOptionShouldResume;
                  NSArray<NativeAudioPlayerHandle *> *handles = [strongSelf currentHandles];
                  if (typeValue == AVAudioSessionInterruptionTypeBegan) {
                    for (NativeAudioPlayerHandle *handle in handles) {
                      [handle interruptionBegan];
                    }
                    [strongSelf deactivateSessionIfNeeded];
                  } else if (typeValue == AVAudioSessionInterruptionTypeEnded) {
                    for (NativeAudioPlayerHandle *handle in handles) {
                      [handle interruptionEndedShouldResume:shouldResume];
                    }
                  }
                }];
  }
  return self;
}

- (void)destroy {
  [_lock lock];
  _destroyed = YES;
  NSArray<NativeAudioPlayerHandle *> *handles = [_playersByID allValues];
  [_playersByID removeAllObjects];
  [_lock unlock];
  if (_interruptionObserver != nil) {
    [[NSNotificationCenter defaultCenter] removeObserver:_interruptionObserver];
    _interruptionObserver = nil;
  }
  dispatch_async(dispatch_get_main_queue(), ^{
    for (NativeAudioPlayerHandle *handle in handles) {
      [handle teardown];
    }
    [self deactivateSession];
  });
}

#pragma mark - Module methods

- (void)create:(NSDictionary *)options callback:(LynxCallbackBlock)callback {
  NSString *identifier = [options[@"id"] isKindOfClass:[NSString class]] ? options[@"id"] : @"";
  NSString *uri = [options[@"uri"] isKindOfClass:[NSString class]] ? options[@"uri"] : @"";
  NSString *usage = [options[@"usage"] isKindOfClass:[NSString class]] ? options[@"usage"] : @"media";
  BOOL autoPlay = [options[@"autoPlay"] boolValue];
  double progressIntervalMs =
      [options[@"progressIntervalMs"] isKindOfClass:[NSNumber class]]
          ? [options[@"progressIntervalMs"] doubleValue]
          : kDefaultProgressIntervalMs;

  [_lock lock];
  BOOL canCreate = !_destroyed && _playersByID[identifier] == nil;
  [_lock unlock];
  if (!canCreate) {
    callback(_destroyed ? @"AudioPlayer host has been destroyed"
                        : @"AudioPlayer ID already exists");
    return;
  }

  dispatch_async(dispatch_get_main_queue(), ^{
    [self->_lock lock];
    BOOL stillPossible = !self->_destroyed && self->_playersByID[identifier] == nil;
    [self->_lock unlock];
    if (!stillPossible) {
      callback(self->_destroyed ? @"AudioPlayer host has been destroyed"
                          : @"AudioPlayer ID already exists");
      return;
    }
    if (identifier.length == 0 || identifier.length > 128 ||
        [identifier rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:
                                                  @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-"]
                                                  invertedSet]
                                     options:0
                                       range:NSMakeRange(0, identifier.length)].location != NSNotFound) {
      callback(@"Invalid AudioPlayer ID");
      return;
    }
    NSURL *url = [NSURL URLWithString:uri];
    if (url == nil || !([url.scheme.lowercaseString isEqualToString:@"file"])) {
      callback(@"AudioPlayer only supports local file:// sources");
      return;
    }
    if (![usage isEqualToString:@"media"] && ![usage isEqualToString:@"ambient"] &&
        ![usage isEqualToString:@"alarm"] && ![usage isEqualToString:@"notification"]) {
      callback(@"Invalid AudioPlayer usage");
      return;
    }
    if (progressIntervalMs < 50 || progressIntervalMs > 10000) {
      callback(@"progressIntervalMs must be between 50 and 10000");
      return;
    }

    NativeAudioPlayerHandle *handle = [[NativeAudioPlayerHandle alloc]
        initWithIdentifier:identifier
                      usage:usage
          progressIntervalMs:progressIntervalMs];
    handle.module = self;
    NSString *prepareError = nil;
    if (![handle prepareWithURI:url error:&prepareError]) {
      callback(prepareError ?: @"read-failed: Unable to open the audio source");
      return;
    }
    [_lock lock];
    _playersByID[identifier] = handle;
    [_lock unlock];
    [handle emitEvent:@{
      @"type" : @"state",
      @"state" : kStateLoading,
      @"positionMs" : @0,
      @"durationMs" : @0,
    }];
    [handle finishPreparingWithAutoPlay:autoPlay];
    [self deactivateSessionIfNeeded];
    callback(@"");
  });
}

- (void)play:(NSString *)identifier callback:(LynxCallbackBlock)callback {
  [self performOnHandle:identifier callback:callback block:^(NativeAudioPlayerHandle *handle) {
    callback([handle play]);
    [self deactivateSessionIfNeeded];
  }];
}

- (void)pause:(NSString *)identifier callback:(LynxCallbackBlock)callback {
  [self performOnHandle:identifier callback:callback block:^(NativeAudioPlayerHandle *handle) {
    callback([handle pause]);
    [self deactivateSessionIfNeeded];
  }];
}

- (void)seek:(NSString *)identifier
   positionMs:(NSInteger)positionMs
     callback:(LynxCallbackBlock)callback {
  [self performOnHandle:identifier callback:callback block:^(NativeAudioPlayerHandle *handle) {
    callback([handle seekToPositionMs:positionMs]);
  }];
}

- (void)stop:(NSString *)identifier callback:(LynxCallbackBlock)callback {
  [self performOnHandle:identifier callback:callback block:^(NativeAudioPlayerHandle *handle) {
    callback([handle stop]);
    [self deactivateSessionIfNeeded];
  }];
}

- (void)release:(NSString *)identifier callback:(LynxCallbackBlock)callback {
  dispatch_async(dispatch_get_main_queue(), ^{
    [_lock lock];
    NativeAudioPlayerHandle *handle = _destroyed ? nil : _playersByID[identifier];
    if (handle != nil) {
      [_playersByID removeObjectForKey:identifier];
    }
    [_lock unlock];
    if (handle == nil) {
      callback(@"Unknown AudioPlayer ID");
      return;
    }
    [handle teardown];
    [self deactivateSessionIfNeeded];
    callback(@"");
  });
}

- (void)setRate:(NSString *)identifier
           rate:(double)rate
       callback:(LynxCallbackBlock)callback {
  [self performOnHandle:identifier callback:callback block:^(NativeAudioPlayerHandle *handle) {
    callback([handle setRate:(float)rate]);
  }];
}

- (void)setVolume:(NSString *)identifier
           volume:(double)volume
         callback:(LynxCallbackBlock)callback {
  [self performOnHandle:identifier callback:callback block:^(NativeAudioPlayerHandle *handle) {
    callback([handle setVolume:(float)volume]);
  }];
}

- (void)getProps:(NSString *)identifier callback:(LynxCallbackBlock)callback {
  [self performOnHandle:identifier callback:callback block:^(NativeAudioPlayerHandle *handle) {
    callback([handle propsJSON]);
  }];
}

#pragma mark - Helpers

- (NSArray<NativeAudioPlayerHandle *> *)currentHandles {
  [_lock lock];
  NSArray<NativeAudioPlayerHandle *> *handles = [_playersByID allValues];
  [_lock unlock];
  return handles;
}

- (void)performOnHandle:(NSString *)identifier
               callback:(LynxCallbackBlock)callback
                  block:(void (^)(NativeAudioPlayerHandle *))block {
  dispatch_async(dispatch_get_main_queue(), ^{
    [_lock lock];
    NativeAudioPlayerHandle *handle = _destroyed ? nil : _playersByID[identifier];
    [_lock unlock];
    if (handle == nil) {
      callback(@"Unknown AudioPlayer ID");
      return;
    }
    block(handle);
  });
}

- (void)deactivateSessionIfNeeded {
  // Deactivate only when this module owns no playing player, so background
  // music from other apps can resume after our content pauses or ends.
  for (NativeAudioPlayerHandle *handle in [self currentHandles]) {
    if ([handle.state isEqualToString:kStatePlaying]) {
      return;
    }
  }
  [self deactivateSession];
}

- (void)deactivateSession {
  NSError *error = nil;
  [[AVAudioSession sharedInstance] setActive:NO
                                 withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation
                                       error:&error];
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

@end
