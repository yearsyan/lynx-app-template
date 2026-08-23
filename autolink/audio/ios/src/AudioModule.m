#import "AudioModule.h"

#import <Lynx/LynxContext.h>

static NSString *const kEventName = @"audioPlayer";
static NSString *const kRecorderEventName = @"audioRecorder";

// Forward declaration so NativeAudioPlayerHandle / NativeAudioRecorderHandle
// can emit through the module before the module's implementation section is
// visible.
@interface AudioModule ()
- (void)emitEventWithIdentifier:(NSString *)identifier payload:(NSDictionary *)payload;
- (void)deactivateSessionIfNeeded;
- (void)emitRecorderEventWithIdentifier:(NSString *)identifier
                                payload:(NSDictionary *)payload;
- (void)recordingSessionEnded;
@end
static NSString *const kStateLoading = @"loading";
static NSString *const kStatePaused = @"paused";
static NSString *const kStatePlaying = @"playing";
static NSString *const kStateStopped = @"stopped";
static NSString *const kRecorderStateIdle = @"idle";
static NSString *const kRecorderStateRecording = @"recording";
static NSString *const kRecorderStatePaused = @"paused";
static NSString *const kRecorderStateStopped = @"stopped";
static NSString *const kRecorderStateFailed = @"failed";
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
@property (nonatomic, weak) AudioModule *module;

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
  AudioModule *module = self.module;
  if (module == nil) {
    return;
  }
  [module emitEventWithIdentifier:_identifier payload:payload];
}

@end

/// One microphone recorder writing AAC into the caches directory. All work
/// happens on the main queue; currentTime advances only while recording, so
/// it doubles as the duration source even across pauses.
@interface NativeAudioRecorderHandle : NSObject <AVAudioRecorderDelegate>

@property (nonatomic, copy, readonly) NSString *identifier;
@property (nonatomic, copy, readonly) NSString *state;
@property (nonatomic, weak) AudioModule *module;

- (instancetype)initWithIdentifier:(NSString *)identifier
                   durationLimitMs:(NSInteger)durationLimitMs
                 progressIntervalMs:(NSTimeInterval)progressIntervalMs;

- (NSString *)start;
- (NSString *)pause;
- (NSString *)resume;
- (NSString *)stopResultJSON;
- (void)cancel;
- (NSString *)propsJSON;
- (void)teardown;

@end

@implementation NativeAudioRecorderHandle {
  NSString *_identifier;
  NSInteger _durationLimitMs;
  NSTimeInterval _progressIntervalMs;
  NSString *_state;
  AVAudioRecorder *_recorder;
  NSURL *_outputURL;
  dispatch_source_t _ticker;
  BOOL _delivered;
  NSString *_deliveredURI;
  NSInteger _deliveredDurationMs;
  NSString *_failure;
}

- (instancetype)initWithIdentifier:(NSString *)identifier
                   durationLimitMs:(NSInteger)durationLimitMs
                 progressIntervalMs:(NSTimeInterval)progressIntervalMs {
  self = [super init];
  if (self) {
    _identifier = [identifier copy];
    _durationLimitMs = durationLimitMs;
    _progressIntervalMs = progressIntervalMs;
    _state = kRecorderStateIdle;
  }
  return self;
}

- (NSString *)identifier {
  return _identifier;
}

- (NSString *)state {
  return _state;
}

#pragma mark - Commands

- (NSString *)start {
  if (![kRecorderStateIdle isEqualToString:_state]
      && ![kRecorderStateStopped isEqualToString:_state]) {
    return @"AudioRecorder has already been started";
  }
  AVAudioSession *session = [AVAudioSession sharedInstance];
  if ([session recordPermission] != AVAudioSessionRecordPermissionGranted) {
    return @"microphone permission is required (request it via the Permissions module)";
  }
  NSError *urlError = nil;
  NSURL *url = [self recordingURL:&urlError];
  if (url == nil) {
    return urlError.localizedDescription ?: @"Unable to prepare the recording file";
  }
  if ([kRecorderStateStopped isEqualToString:_state]) {
    // A second take replaces the previous file entirely.
    _delivered = NO;
    _deliveredURI = nil;
  }
  NSDictionary *settings = @{
    AVFormatIDKey : @(kAudioFormatMPEG4AAC),
    AVSampleRateKey : @(44100.0),
    AVNumberOfChannelsKey : @(1),
    AVEncoderBitRateKey : @(128000),
    AVEncoderAudioQualityKey : @(AVAudioQualityHigh),
  };
  NSError *recorderError = nil;
  AVAudioRecorder *recorder = [[AVAudioRecorder alloc] initWithURL:url
                                                           settings:settings
                                                              error:&recorderError];
  if (recorder == nil) {
    return recorderError.localizedDescription ?: @"Unable to create the recorder";
  }
  [self activateSession];
  recorder.delegate = self;
  recorder.meteringEnabled = NO;
  if (![recorder record]) {
    return @"Unable to start the recording";
  }
  _recorder = recorder;
  _outputURL = url;
  _state = kRecorderStateRecording;
  [self emitState];
  [self startTicker];
  return @"";
}

- (NSString *)pause {
  if (![kRecorderStateRecording isEqualToString:_state]) {
    return [kRecorderStateIdle isEqualToString:_state] ? @"AudioRecorder has not been started" : @"";
  }
  [self stopTicker];
  [_recorder pause];
  _state = kRecorderStatePaused;
  [self emitState];
  return @"";
}

- (NSString *)resume {
  if (![kRecorderStatePaused isEqualToString:_state]) {
    return [kRecorderStateIdle isEqualToString:_state] ? @"AudioRecorder has not been started" : @"";
  }
  [self activateSession];
  if (![_recorder record]) {
    return @"Unable to resume the recording";
  }
  _state = kRecorderStateRecording;
  [self emitState];
  [self startTicker];
  return @"";
}

- (NSString *)stopResultJSON {
  if (![kRecorderStateRecording isEqualToString:_state]
      && ![kRecorderStatePaused isEqualToString:_state]) {
    return _delivered ? [self resultJSON] : [self stopError];
  }
  [self stopTicker];
  NSInteger durationMs = [self durationMs];
  [_recorder stop];
  _recorder.delegate = nil;
  _recorder = nil;
  _state = kRecorderStateStopped;
  _delivered = YES;
  _deliveredURI = _outputURL.absoluteString;
  _deliveredDurationMs = durationMs;
  [self emitState];
  [self.module recordingSessionEnded];
  return [self resultJSON];
}

- (void)cancel {
  [self stopTicker];
  [_recorder stop];
  _recorder.delegate = nil;
  _recorder = nil;
  [[NSFileManager defaultManager] removeItemAtURL:_outputURL error:nil];
  _outputURL = nil;
  _delivered = NO;
  _deliveredURI = nil;
  _state = kRecorderStateIdle;
  [self.module recordingSessionEnded];
}

/// Duration-limit stop triggered by the ticker: same delivery as an explicit
/// stop, announced through the `end` event instead of a command callback.
- (void)stopFromLimit {
  if (![kRecorderStateRecording isEqualToString:_state]
      && ![kRecorderStatePaused isEqualToString:_state]) {
    return;
  }
  [self stopTicker];
  NSInteger durationMs = [self durationMs];
  [_recorder stop];
  _recorder.delegate = nil;
  _recorder = nil;
  _state = kRecorderStateStopped;
  _delivered = YES;
  _deliveredURI = _outputURL.absoluteString;
  _deliveredDurationMs = durationMs;
  [self emitState];
  [self emitEvent:@{
    @"type" : @"end",
    @"uri" : _deliveredURI,
    @"durationMs" : @(_deliveredDurationMs),
  }];
  [self.module recordingSessionEnded];
}

- (NSString *)propsJSON {
  NSDictionary *props = @{
    @"state" : _state,
    @"durationMs" : @([self durationMs]),
    @"uri" : _deliveredURI ?: NSNull.null,
  };
  NSData *data = [NSJSONSerialization dataWithJSONObject:props options:0 error:nil];
  return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]
              : @"{\"error\":\"AudioRecorder serialization failed\"}";
}

- (void)teardown {
  if ([_state isEqualToString:kRecorderStateRecording]
      || [_state isEqualToString:kRecorderStatePaused]) {
    [self stopTicker];
    [_recorder stop];
    [self.module recordingSessionEnded];
  }
  _recorder.delegate = nil;
  _recorder = nil;
  if (!_delivered) {
    [[NSFileManager defaultManager] removeItemAtURL:_outputURL error:nil];
  }
  _outputURL = nil;
  _state = kRecorderStateStopped;
}

#pragma mark - AVAudioRecorderDelegate

- (void)audioRecorderEncodeErrorDidOccur:(AVAudioRecorder *)recorder
                                   error:(NSError *_Nullable)error {
  if (recorder != _recorder) {
    return;
  }
  [self stopTicker];
  _recorder.delegate = nil;
  _recorder = nil;
  _state = kRecorderStateFailed;
  _failure = error.localizedDescription ?: @"Recording failed";
  [[NSFileManager defaultManager] removeItemAtURL:_outputURL error:nil];
  _outputURL = nil;
  [self emitState];
  [self emitError:_failure];
  [self.module recordingSessionEnded];
}

#pragma mark - Internals

- (NSInteger)durationMs {
  if (_recorder == nil) {
    return _delivered ? _deliveredDurationMs : 0;
  }
  return (NSInteger)lround(_recorder.currentTime * 1000.0);
}

- (void)activateSession {
  AVAudioSession *session = [AVAudioSession sharedInstance];
  NSError *error = nil;
  [session setCategory:AVAudioSessionCategoryPlayAndRecord error:&error];
  if (error == nil) {
    [session setActive:YES error:&error];
  }
}

- (nullable NSURL *)recordingURL:(NSError **)error {
  NSFileManager *manager = NSFileManager.defaultManager;
  NSURL *cache = [manager URLForDirectory:NSCachesDirectory
                                 inDomain:NSUserDomainMask
                        appropriateForURL:nil
                                   create:YES
                                    error:error];
  if (cache == nil) return nil;
  NSURL *directory = [[cache URLByAppendingPathComponent:@"LynxFiles" isDirectory:YES]
      URLByAppendingPathComponent:@"recordings" isDirectory:YES];
  if (![manager createDirectoryAtURL:directory
          withIntermediateDirectories:YES
                           attributes:nil
                                error:error]) {
    return nil;
  }
  if (_outputURL != nil
      && [[NSFileManager defaultManager] fileExistsAtPath:_outputURL.path]
      && ![[NSFileManager defaultManager] removeItemAtURL:_outputURL error:error]) {
    return nil;
  }
  NSString *name = [NSString stringWithFormat:@"%@.m4a", _identifier];
  return [directory URLByAppendingPathComponent:name isDirectory:NO];
}

- (NSString *)resultJSON {
  NSDictionary *attributes =
      [NSFileManager.defaultManager attributesOfItemAtPath:_outputURL.path error:nil];
  NSNumber *size = [attributes isKindOfClass:NSDictionary.class] ? attributes[NSFileSize] : nil;
  NSDictionary *result = @{
    @"uri" : _deliveredURI ?: NSNull.null,
    @"durationMs" : @(_deliveredDurationMs),
    @"sizeBytes" : size ?: NSNull.null,
  };
  NSData *data = [NSJSONSerialization dataWithJSONObject:result options:0 error:nil];
  return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]
              : @"{\"error\":\"AudioRecorder serialization failed\"}";
}

- (NSString *)stopError {
  if ([_state isEqualToString:kRecorderStateFailed] && _failure.length > 0) {
    return _failure;
  }
  return @"AudioRecorder has not been started";
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
  __weak NativeAudioRecorderHandle *weakSelf = self;
  dispatch_source_set_event_handler(ticker, ^{
    NativeAudioRecorderHandle *strongSelf = weakSelf;
    if (strongSelf == nil) {
      return;
    }
    if (![strongSelf->_state isEqualToString:kRecorderStateRecording]) {
      return;
    }
    NSInteger duration = [strongSelf durationMs];
    [strongSelf emitEvent:@{
      @"type" : @"progress",
      @"state" : strongSelf->_state,
      @"durationMs" : @(duration),
    }];
    if (strongSelf->_durationLimitMs > 0
        && duration >= strongSelf->_durationLimitMs) {
      [strongSelf stopFromLimit];
    }
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

- (void)emitState {
  [self emitEvent:@{
    @"type" : @"state",
    @"state" : _state,
    @"durationMs" : @([self durationMs]),
  }];
}

- (void)emitError:(NSString *)message {
  [self emitEvent:@{ @"type" : @"error", @"error" : message }];
}

- (void)emitEvent:(NSDictionary *)payload {
  AudioModule *module = self.module;
  if (module == nil) {
    return;
  }
  [module emitRecorderEventWithIdentifier:_identifier payload:payload];
}

@end

// The @LynxNativeModule annotation is what cocoapods-lynx-library scans for;
// it expands to a harmless ObjC forward declaration when compiled.
// Exported to Lynx as `Audio`.
@LynxNativeModule("Audio")
@implementation AudioModule {
  LynxContext *_context;
  NSLock *_lock;
  NSMutableDictionary<NSString *, NativeAudioPlayerHandle *> *_playersByID;
  NSMutableDictionary<NSString *, NativeAudioRecorderHandle *> *_recordersByID;
  id _interruptionObserver;
  BOOL _destroyed;
}

+ (NSString *)name {
  return @"Audio";
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
    @"recorderCreate" : NSStringFromSelector(@selector(recorderCreate:callback:)),
    @"recorderStart" : NSStringFromSelector(@selector(recorderStart:callback:)),
    @"recorderPause" : NSStringFromSelector(@selector(recorderPause:callback:)),
    @"recorderResume" : NSStringFromSelector(@selector(recorderResume:callback:)),
    @"recorderStop" : NSStringFromSelector(@selector(recorderStop:callback:)),
    @"recorderCancel" : NSStringFromSelector(@selector(recorderCancel:callback:)),
    @"recorderGetProps" : NSStringFromSelector(@selector(recorderGetProps:callback:)),
    @"recorderRelease" : NSStringFromSelector(@selector(recorderRelease:callback:)),
  };
}

- (instancetype)initWithLynxContext:(LynxContext *)context {
  self = [super init];
  if (self) {
    _context = context;
    _lock = [[NSLock alloc] init];
    _playersByID = [[NSMutableDictionary alloc] init];
    _recordersByID = [[NSMutableDictionary alloc] init];
    __weak AudioModule *weakSelf = self;
    _interruptionObserver = [[NSNotificationCenter defaultCenter]
        addObserverForName:AVAudioSessionInterruptionNotification
                    object:[AVAudioSession sharedInstance]
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *notification) {
                  AudioModule *strongSelf = weakSelf;
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
  NSArray<NativeAudioRecorderHandle *> *recorders = [_recordersByID allValues];
  [_recordersByID removeAllObjects];
  [_lock unlock];
  if (_interruptionObserver != nil) {
    [[NSNotificationCenter defaultCenter] removeObserver:_interruptionObserver];
    _interruptionObserver = nil;
  }
  dispatch_async(dispatch_get_main_queue(), ^{
    for (NativeAudioPlayerHandle *handle in handles) {
      [handle teardown];
    }
    for (NativeAudioRecorderHandle *recorder in recorders) {
      [recorder teardown];
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

- (void)recorderCreate:(NSDictionary *)options callback:(LynxCallbackBlock)callback {
  NSString *identifier = [options[@"id"] isKindOfClass:[NSString class]] ? options[@"id"] : @"";
  double durationLimitMs =
      [options[@"durationLimitMs"] isKindOfClass:[NSNumber class]]
          ? [options[@"durationLimitMs"] doubleValue]
          : 0;
  double progressIntervalMs =
      [options[@"progressIntervalMs"] isKindOfClass:[NSNumber class]]
          ? [options[@"progressIntervalMs"] doubleValue]
          : kDefaultProgressIntervalMs;

  [_lock lock];
  BOOL canCreate = !_destroyed && _recordersByID[identifier] == nil;
  [_lock unlock];
  if (!canCreate) {
    callback(_destroyed ? @"Audio host has been destroyed"
                        : @"AudioRecorder ID already exists");
    return;
  }
  if (identifier.length == 0 || identifier.length > 128 ||
      [identifier rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:
                                              @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-"]
                                              invertedSet]
                           options:0
                             range:NSMakeRange(0, identifier.length)].location != NSNotFound) {
    callback(@"Invalid AudioRecorder ID");
    return;
  }
  if ((durationLimitMs != 0 && durationLimitMs < 100) || durationLimitMs > 600000) {
    callback(@"durationLimitMs must be between 100 and 600000, or 0 to disable");
    return;
  }
  if (progressIntervalMs < 50 || progressIntervalMs > 10000) {
    callback(@"progressIntervalMs must be between 50 and 10000");
    return;
  }

  dispatch_async(dispatch_get_main_queue(), ^{
    [self->_lock lock];
    BOOL stillPossible = !self->_destroyed && self->_recordersByID[identifier] == nil;
    [self->_lock unlock];
    if (!stillPossible) {
      callback(self->_destroyed ? @"Audio host has been destroyed"
                                : @"AudioRecorder ID already exists");
      return;
    }
    NativeAudioRecorderHandle *handle = [[NativeAudioRecorderHandle alloc]
        initWithIdentifier:identifier
           durationLimitMs:(NSInteger)durationLimitMs
         progressIntervalMs:progressIntervalMs];
    handle.module = self;
    [self->_lock lock];
    self->_recordersByID[identifier] = handle;
    [self->_lock unlock];
    callback(@"");
  });
}

- (void)recorderStart:(NSString *)identifier callback:(LynxCallbackBlock)callback {
  [self performOnRecorder:identifier callback:callback block:^(NativeAudioRecorderHandle *handle) {
    callback([handle start]);
  }];
}

- (void)recorderPause:(NSString *)identifier callback:(LynxCallbackBlock)callback {
  [self performOnRecorder:identifier callback:callback block:^(NativeAudioRecorderHandle *handle) {
    callback([handle pause]);
  }];
}

- (void)recorderResume:(NSString *)identifier callback:(LynxCallbackBlock)callback {
  [self performOnRecorder:identifier callback:callback block:^(NativeAudioRecorderHandle *handle) {
    callback([handle resume]);
  }];
}

- (void)recorderStop:(NSString *)identifier callback:(LynxCallbackBlock)callback {
  [self performOnRecorder:identifier callback:callback block:^(NativeAudioRecorderHandle *handle) {
    callback([handle stopResultJSON]);
  }];
}

- (void)recorderCancel:(NSString *)identifier callback:(LynxCallbackBlock)callback {
  [self removeRecorder:identifier callback:callback block:^(NativeAudioRecorderHandle *handle) {
    [handle cancel];
    callback(@"");
  }];
}

- (void)recorderGetProps:(NSString *)identifier callback:(LynxCallbackBlock)callback {
  [self performOnRecorder:identifier callback:callback block:^(NativeAudioRecorderHandle *handle) {
    callback([handle propsJSON]);
  }];
}

- (void)recorderRelease:(NSString *)identifier callback:(LynxCallbackBlock)callback {
  [self removeRecorder:identifier callback:callback block:^(NativeAudioRecorderHandle *handle) {
    [handle teardown];
    callback(@"");
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

- (void)performOnRecorder:(NSString *)identifier
                 callback:(LynxCallbackBlock)callback
                    block:(void (^)(NativeAudioRecorderHandle *))block {
  dispatch_async(dispatch_get_main_queue(), ^{
    [_lock lock];
    NativeAudioRecorderHandle *handle = _destroyed ? nil : _recordersByID[identifier];
    [_lock unlock];
    if (handle == nil) {
      callback(@"Unknown AudioRecorder ID");
      return;
    }
    block(handle);
  });
}

- (void)removeRecorder:(NSString *)identifier
              callback:(LynxCallbackBlock)callback
                 block:(void (^)(NativeAudioRecorderHandle *))block {
  dispatch_async(dispatch_get_main_queue(), ^{
    [_lock lock];
    NativeAudioRecorderHandle *handle = _destroyed ? nil : _recordersByID[identifier];
    if (handle != nil) {
      [_recordersByID removeObjectForKey:identifier];
    }
    [_lock unlock];
    if (handle == nil) {
      callback(@"Unknown AudioRecorder ID");
      return;
    }
    block(handle);
  });
}

- (void)recordingSessionEnded {
  // Leave the shared session active while a player is audible; otherwise
  // hand it back so background music from other apps can resume.
  for (NativeAudioPlayerHandle *handle in [self currentHandles]) {
    if ([handle.state isEqualToString:kStatePlaying]) {
      return;
    }
  }
  [self deactivateSession];
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
  [self emitGlobalEvent:kEventName identifier:identifier payload:payload];
}

- (void)emitRecorderEventWithIdentifier:(NSString *)identifier
                                payload:(NSDictionary *)payload {
  [self emitGlobalEvent:kRecorderEventName identifier:identifier payload:payload];
}

- (void)emitGlobalEvent:(NSString *)eventName
              identifier:(NSString *)identifier
                payload:(NSDictionary *)payload {
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
    [context sendGlobalEvent:eventName withParams:@[event]];
  });
}

@end
