#import "DownloadManagerModule.h"

#import <Lynx/LynxContext.h>

static NSString *const DMEventName = @"downloadManager";
static NSString *const DMErrorDomain = @"com.lynxapp.autolink.downloadmanager";

static NSString *const DMStateQueued = @"queued";
static NSString *const DMStateRunning = @"running";
static NSString *const DMStatePaused = @"paused";
static NSString *const DMStateCompleted = @"completed";
static NSString *const DMStateFailed = @"failed";
static NSString *const DMStateCancelled = @"cancelled";
static const NSInteger DMPersistenceVersion = 1;
static const int64_t DMMaxSafeInteger = 9007199254740991LL;

@interface DMDownloadRecord : NSObject
@property(nonatomic, copy) NSString *identifier;
@property(nonatomic, copy) NSString *url;
@property(nonatomic, copy) NSString *fileName;
@property(nonatomic, copy) NSDictionary<NSString *, NSString *> *headers;
@property(nonatomic, assign) NSInteger progressIntervalMs;
@property(nonatomic, assign) BOOL persistProgress;
@property(nonatomic, copy) NSString *state;
@property(nonatomic, assign) int64_t bytesDownloaded;
@property(nonatomic, nullable, strong) NSNumber *totalBytes;
@property(nonatomic, nullable, copy) NSString *fileUri;
@property(nonatomic, nullable, copy) NSString *errorMessage;
@property(nonatomic, assign) int64_t createdAt;
@property(nonatomic, assign) int64_t updatedAt;
@property(nonatomic, assign) int64_t lastProgressEventAt;
@property(nonatomic, nullable, strong) NSURLSessionTask *nativeTask;
@property(nonatomic, nullable, strong) NSData *resumeData;
@property(nonatomic, nullable, strong) NSFileHandle *fileHandle;
@property(nonatomic, nullable, copy) NSString *rangeValidator;
@property(nonatomic, assign) int64_t requestedOffset;
@end

@implementation DMDownloadRecord
@end

@class DMDownloadStore;

@interface DownloadManagerModule ()
- (void)emitDownloadEvent:(NSString *)type task:(NSDictionary *)task;
@end

@interface DMDownloadStore : NSObject <NSURLSessionDownloadDelegate, NSURLSessionDataDelegate>
+ (instancetype)shared;
- (void)addSink:(DownloadManagerModule *)sink;
- (void)removeSink:(DownloadManagerModule *)sink;
- (nullable NSDictionary *)enqueue:(NSDictionary *)options error:(NSError **)error;
- (nullable NSDictionary *)pause:(NSString *)identifier error:(NSError **)error;
- (nullable NSDictionary *)resume:(NSString *)identifier error:(NSError **)error;
- (nullable NSDictionary *)cancel:(NSString *)identifier error:(NSError **)error;
- (BOOL)remove:(NSString *)identifier deleteFile:(BOOL)deleteFile error:(NSError **)error;
- (nullable NSDictionary *)task:(NSString *)identifier;
- (NSArray<NSDictionary *> *)tasks;
- (void)loadPersistedRecords;
- (BOOL)persistRecord:(DMDownloadRecord *)record error:(NSError **)error;
- (void)persistRecordQuietly:(DMDownloadRecord *)record;
- (BOOL)deletePersistedRecord:(DMDownloadRecord *)record error:(NSError **)error;
- (nullable NSURL *)partialURL:(DMDownloadRecord *)record error:(NSError **)error;
- (nullable NSNumber *)fileSizeAtURL:(NSURL *)url;
- (void)closeFile:(DMDownloadRecord *)record;
- (void)finishPersistentRecord:(DMDownloadRecord *)record;
- (void)failPersistentRecord:(DMDownloadRecord *)record message:(NSString *)message;
- (nullable NSURLSessionDataTask *)newPersistentTaskForRecord:(DMDownloadRecord *)record
                                                        error:(NSError **)error;
- (nullable NSNumber *)contentRangeStart:(nullable NSString *)value;
- (nullable NSNumber *)contentRangeTotal:(nullable NSString *)value;
- (nullable NSString *)responseValidator:(NSHTTPURLResponse *)response;
- (nullable DMDownloadRecord *)recordFromPersistedDictionary:(NSDictionary *)value
                                                        error:(NSError **)error;
- (nullable NSURL *)persistenceDirectoryURL:(NSError **)error;
- (nullable NSURL *)metadataURL:(DMDownloadRecord *)record error:(NSError **)error;
- (BOOL)isSafeIdentifier:(id)value;
- (BOOL)isSafeURL:(id)value;
- (BOOL)isSafeFileName:(id)value;
- (BOOL)areSafeHeaders:(id)value;
- (BOOL)isKnownState:(id)value;
- (BOOL)isSafeInteger:(id)value;
@end

@implementation DMDownloadStore {
  dispatch_queue_t _queue;
  NSMutableDictionary<NSString *, DMDownloadRecord *> *_records;
  NSHashTable<DownloadManagerModule *> *_sinks;
  NSURLSession *_session;
}

+ (instancetype)shared {
  static DMDownloadStore *store;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    store = [[DMDownloadStore alloc] initPrivate];
  });
  return store;
}

- (instancetype)init {
  return [DMDownloadStore shared];
}

- (instancetype)initPrivate {
  self = [super init];
  if (self) {
    _queue = dispatch_queue_create(
        "com.lynxapp.autolink.downloadmanager.store", DISPATCH_QUEUE_SERIAL);
    _records = [NSMutableDictionary dictionary];
    _sinks = [NSHashTable weakObjectsHashTable];
    NSOperationQueue *delegateQueue = [[NSOperationQueue alloc] init];
    delegateQueue.maxConcurrentOperationCount = 1;
    NSURLSessionConfiguration *configuration =
        [NSURLSessionConfiguration defaultSessionConfiguration];
    configuration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    _session = [NSURLSession sessionWithConfiguration:configuration
                                             delegate:self
                                        delegateQueue:delegateQueue];
    [self loadPersistedRecords];
  }
  return self;
}

- (void)addSink:(DownloadManagerModule *)sink {
  dispatch_async(_queue, ^{
    [self->_sinks addObject:sink];
  });
}

- (void)removeSink:(DownloadManagerModule *)sink {
  dispatch_async(_queue, ^{
    [self->_sinks removeObject:sink];
  });
}

- (nullable NSDictionary *)enqueue:(NSDictionary *)options error:(NSError **)error {
  __block NSDictionary *result;
  __block NSError *operationError;
  dispatch_sync(_queue, ^{
    NSString *identifier = options[@"id"];
    if (self->_records[identifier] != nil) {
      operationError = [self error:@"Download task ID already exists"];
      return;
    }
    DMDownloadRecord *record = [[DMDownloadRecord alloc] init];
    record.identifier = identifier;
    record.url = options[@"url"];
    record.fileName = options[@"fileName"];
    record.headers = options[@"headers"] ?: @{};
    record.progressIntervalMs = [options[@"progressIntervalMs"] integerValue];
    record.persistProgress = [options[@"persistProgress"] boolValue];
    record.state = DMStateQueued;
    record.createdAt = [self now];
    record.updatedAt = record.createdAt;
    self->_records[identifier] = record;

    if (record.persistProgress && ![self persistRecord:record error:&operationError]) {
      [self->_records removeObjectForKey:identifier];
      return;
    }

    NSError *requestError;
    NSURLSessionTask *task = [self newTaskForRecord:record
                                        resumeData:nil
                                             error:&requestError];
    if (task == nil) {
      [self->_records removeObjectForKey:identifier];
      [self deletePersistedRecord:record error:nil];
      operationError = requestError;
      return;
    }
    record.nativeTask = task;
    record.state = DMStateRunning;
    record.updatedAt = [self now];
    result = [self snapshot:record];
    [self persistRecordQuietly:record];
    [task resume];
    [self emit:@"state" task:result];
  });
  if (error != NULL) *error = operationError;
  return result;
}

- (nullable NSDictionary *)pause:(NSString *)identifier error:(NSError **)error {
  __block NSDictionary *result;
  __block NSError *operationError;
  dispatch_sync(_queue, ^{
    DMDownloadRecord *record = [self requireRecord:identifier error:&operationError];
    if (record == nil) return;
    if (![record.state isEqualToString:DMStateRunning]
        && ![record.state isEqualToString:DMStateQueued]) {
      operationError = [self error:@"Download task is not running"];
      return;
    }
    NSURLSessionTask *task = record.nativeTask;
    record.nativeTask = nil;
    record.state = DMStatePaused;
    record.errorMessage = nil;
    record.updatedAt = [self now];
    result = [self snapshot:record];
    [self closeFile:record];
    [self persistRecordQuietly:record];
    [self emit:@"state" task:result];
    if (record.persistProgress) {
      [task cancel];
    } else {
      [(NSURLSessionDownloadTask *)task
          cancelByProducingResumeData:^(NSData *_Nullable resumeData) {
            dispatch_async(self->_queue, ^{
              DMDownloadRecord *current = self->_records[identifier];
              if (current == record && [current.state isEqualToString:DMStatePaused]) {
                current.resumeData = resumeData;
              }
            });
          }];
    }
  });
  if (error != NULL) *error = operationError;
  return result;
}

- (nullable NSDictionary *)resume:(NSString *)identifier error:(NSError **)error {
  __block NSDictionary *result;
  __block NSError *operationError;
  dispatch_sync(_queue, ^{
    DMDownloadRecord *record = [self requireRecord:identifier error:&operationError];
    if (record == nil) return;
    if (![record.state isEqualToString:DMStatePaused]
        && ![record.state isEqualToString:DMStateFailed]) {
      operationError = [self error:@"Only paused or failed downloads can resume"];
      return;
    }
    NSData *resumeData = record.resumeData;
    NSError *requestError;
    NSURLSessionTask *task = [self newTaskForRecord:record
                                        resumeData:resumeData
                                             error:&requestError];
    if (task == nil) {
      operationError = requestError;
      return;
    }
    if (!record.persistProgress && resumeData == nil) {
      record.bytesDownloaded = 0;
      record.totalBytes = nil;
    }
    record.resumeData = nil;
    record.nativeTask = task;
    record.state = DMStateRunning;
    record.errorMessage = nil;
    record.fileUri = nil;
    record.updatedAt = [self now];
    result = [self snapshot:record];
    [self persistRecordQuietly:record];
    [task resume];
    [self emit:@"state" task:result];
  });
  if (error != NULL) *error = operationError;
  return result;
}

- (nullable NSDictionary *)cancel:(NSString *)identifier error:(NSError **)error {
  __block NSDictionary *result;
  __block NSError *operationError;
  dispatch_sync(_queue, ^{
    DMDownloadRecord *record = [self requireRecord:identifier error:&operationError];
    if (record == nil) return;
    if ([record.state isEqualToString:DMStateCompleted]) {
      operationError = [self error:@"Completed downloads cannot be cancelled"];
      return;
    }
    if (![record.state isEqualToString:DMStateCancelled]) {
      [record.nativeTask cancel];
      record.nativeTask = nil;
      [self closeFile:record];
      record.resumeData = nil;
      record.state = DMStateCancelled;
      record.bytesDownloaded = 0;
      record.errorMessage = nil;
      record.fileUri = nil;
      record.updatedAt = [self now];
      if (record.persistProgress) {
        NSURL *partial = [self partialURL:record error:nil];
        if (partial != nil) [[NSFileManager defaultManager] removeItemAtURL:partial error:nil];
      }
      [self persistRecordQuietly:record];
      [self emit:@"state" task:[self snapshot:record]];
    }
    result = [self snapshot:record];
  });
  if (error != NULL) *error = operationError;
  return result;
}

- (BOOL)remove:(NSString *)identifier deleteFile:(BOOL)deleteFile error:(NSError **)error {
  __block BOOL success = NO;
  __block NSError *operationError;
  dispatch_sync(_queue, ^{
    DMDownloadRecord *record = [self requireRecord:identifier error:&operationError];
    if (record == nil) return;
    [record.nativeTask cancel];
    [self closeFile:record];
    NSURL *partial = [self partialURL:record error:&operationError];
    if (partial != nil
        && [[NSFileManager defaultManager] fileExistsAtPath:partial.path]
        && ![[NSFileManager defaultManager] removeItemAtURL:partial error:&operationError]) {
      return;
    }
    if (deleteFile) {
      NSURL *destination = [self destinationURL:record error:&operationError];
      if (destination != nil
          && [[NSFileManager defaultManager] fileExistsAtPath:destination.path]
          && ![[NSFileManager defaultManager] removeItemAtURL:destination
                                                       error:&operationError]) {
        return;
      }
    }
    if (![self deletePersistedRecord:record error:&operationError]) return;
    [self->_records removeObjectForKey:identifier];
    success = YES;
  });
  if (error != NULL) *error = operationError;
  return success;
}

- (nullable NSDictionary *)task:(NSString *)identifier {
  __block NSDictionary *result;
  dispatch_sync(_queue, ^{
    DMDownloadRecord *record = self->_records[identifier];
    result = record == nil ? nil : [self snapshot:record];
  });
  return result;
}

- (NSArray<NSDictionary *> *)tasks {
  __block NSArray<NSDictionary *> *result;
  dispatch_sync(_queue, ^{
    NSArray<DMDownloadRecord *> *records = [self->_records.allValues
        sortedArrayUsingComparator:^NSComparisonResult(
            DMDownloadRecord *left, DMDownloadRecord *right) {
          if (left.createdAt < right.createdAt) return NSOrderedAscending;
          if (left.createdAt > right.createdAt) return NSOrderedDescending;
          return NSOrderedSame;
        }];
    NSMutableArray<NSDictionary *> *values = [NSMutableArray array];
    for (DMDownloadRecord *record in records) [values addObject:[self snapshot:record]];
    result = values;
  });
  return result;
}

#pragma mark - NSURLSessionDownloadDelegate

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
      didWriteData:(int64_t)bytesWritten
 totalBytesWritten:(int64_t)totalBytesWritten
totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite {
  dispatch_async(_queue, ^{
    DMDownloadRecord *record = self->_records[downloadTask.taskDescription];
    if (record == nil || record.nativeTask != downloadTask
        || ![record.state isEqualToString:DMStateRunning]) {
      return;
    }
    record.bytesDownloaded = MAX(0, totalBytesWritten);
    record.totalBytes = totalBytesExpectedToWrite > 0
        ? @(totalBytesExpectedToWrite)
        : nil;
    record.updatedAt = [self now];
    if (record.updatedAt - record.lastProgressEventAt >= record.progressIntervalMs) {
      record.lastProgressEventAt = record.updatedAt;
      [self persistRecordQuietly:record];
      [self emit:@"progress" task:[self snapshot:record]];
    }
  });
}

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
didReceiveResponse:(NSURLResponse *)response
 completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler {
  dispatch_async(_queue, ^{
    DMDownloadRecord *record = self->_records[dataTask.taskDescription];
    if (record == nil || !record.persistProgress || record.nativeTask != dataTask
        || ![record.state isEqualToString:DMStateRunning]) {
      completionHandler(NSURLSessionResponseCancel);
      return;
    }
    if (![response isKindOfClass:NSHTTPURLResponse.class]) {
      [self failPersistentRecord:record message:@"Download response was not HTTP"];
      completionHandler(NSURLSessionResponseCancel);
      return;
    }

    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
    NSInteger status = httpResponse.statusCode;
    NSString *contentRange = [httpResponse valueForHTTPHeaderField:@"Content-Range"];
    NSNumber *rangeStart = [self contentRangeStart:contentRange];
    NSNumber *rangeTotal = [self contentRangeTotal:contentRange];
    if (status == 416 && record.requestedOffset > 0
        && rangeTotal != nil && rangeTotal.longLongValue == record.requestedOffset) {
      record.totalBytes = rangeTotal;
      record.bytesDownloaded = record.requestedOffset;
      record.nativeTask = nil;
      [self finishPersistentRecord:record];
      completionHandler(NSURLSessionResponseCancel);
      return;
    }
    if (status < 200 || status >= 300) {
      [self failPersistentRecord:record
                         message:[NSString stringWithFormat:@"HTTP %ld", (long)status]];
      completionHandler(NSURLSessionResponseCancel);
      return;
    }

    BOOL append = record.requestedOffset > 0 && status == 206;
    if ((status == 206 && (rangeStart == nil
                          || rangeStart.longLongValue != record.requestedOffset))) {
      [self failPersistentRecord:record message:@"Server returned an invalid Content-Range"];
      completionHandler(NSURLSessionResponseCancel);
      return;
    }
    if (!append) {
      record.requestedOffset = 0;
      record.bytesDownloaded = 0;
      record.totalBytes = nil;
      record.rangeValidator = [self responseValidator:httpResponse];
    }

    NSError *fileError;
    NSURL *partial = [self partialURL:record error:&fileError];
    NSFileManager *manager = NSFileManager.defaultManager;
    if (partial != nil && ![manager fileExistsAtPath:partial.path]) {
      [manager createFileAtPath:partial.path contents:nil attributes:nil];
    }
    NSFileHandle *handle = partial == nil
        ? nil
        : [NSFileHandle fileHandleForWritingAtPath:partial.path];
    if (handle == nil) {
      [self failPersistentRecord:record
                         message:fileError.localizedDescription ?: @"Unable to open partial file"];
      completionHandler(NSURLSessionResponseCancel);
      return;
    }
    @try {
      if (append) [handle seekToEndOfFile];
      else [handle truncateFileAtOffset:0];
    } @catch (NSException *exception) {
      [handle closeFile];
      [self failPersistentRecord:record message:exception.reason ?: @"Unable to prepare file"];
      completionHandler(NSURLSessionResponseCancel);
      return;
    }
    record.fileHandle = handle;
    record.bytesDownloaded = append ? record.requestedOffset : 0;
    if (rangeTotal != nil) {
      record.totalBytes = rangeTotal;
    } else if (response.expectedContentLength >= 0) {
      int64_t expected = response.expectedContentLength;
      if (expected > DMMaxSafeInteger - (append ? record.requestedOffset : 0)) {
        [handle closeFile];
        record.fileHandle = nil;
        [self failPersistentRecord:record message:@"Invalid or unsupported Content-Length"];
        completionHandler(NSURLSessionResponseCancel);
        return;
      }
      record.totalBytes = @(append ? record.requestedOffset + expected : expected);
    }
    record.updatedAt = [self now];
    [self persistRecordQuietly:record];
    [self emit:@"progress" task:[self snapshot:record]];
    completionHandler(NSURLSessionResponseAllow);
  });
}

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveData:(NSData *)data {
  dispatch_async(_queue, ^{
    DMDownloadRecord *record = self->_records[dataTask.taskDescription];
    if (record == nil || !record.persistProgress || record.nativeTask != dataTask
        || record.fileHandle == nil || ![record.state isEqualToString:DMStateRunning]) {
      return;
    }
    if (data.length > (NSUInteger)(DMMaxSafeInteger - record.bytesDownloaded)) {
      [self failPersistentRecord:record
                         message:@"Download exceeds the JavaScript safe integer limit"];
      [dataTask cancel];
      return;
    }
    if (record.totalBytes != nil) {
      int64_t remaining = record.totalBytes.longLongValue - record.bytesDownloaded;
      if (remaining < 0 || data.length > (NSUInteger)remaining) {
        [self failPersistentRecord:record
                           message:@"Downloaded byte count exceeded Content-Length"];
        [dataTask cancel];
        return;
      }
    }
    @try {
      [record.fileHandle writeData:data];
    } @catch (NSException *exception) {
      [self failPersistentRecord:record
                         message:exception.reason ?: @"Unable to write download"];
      [dataTask cancel];
      return;
    }
    record.bytesDownloaded += (int64_t)data.length;
    record.updatedAt = [self now];
    if (record.updatedAt - record.lastProgressEventAt >= record.progressIntervalMs) {
      record.lastProgressEventAt = record.updatedAt;
      [self persistRecordQuietly:record];
      [self emit:@"progress" task:[self snapshot:record]];
    }
  });
}

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
didFinishDownloadingToURL:(NSURL *)location {
  dispatch_sync(_queue, ^{
    DMDownloadRecord *record = self->_records[downloadTask.taskDescription];
    if (record == nil || record.nativeTask != downloadTask
        || ![record.state isEqualToString:DMStateRunning]) {
      return;
    }
    NSError *moveError;
    NSURL *destination = [self destinationURL:record error:&moveError];
    NSFileManager *manager = [NSFileManager defaultManager];
    if (destination != nil && [manager fileExistsAtPath:destination.path]) {
      [manager removeItemAtURL:destination error:&moveError];
    }
    if (destination != nil && moveError == nil
        && [manager moveItemAtURL:location toURL:destination error:&moveError]) {
      record.nativeTask = nil;
      record.resumeData = nil;
      record.state = DMStateCompleted;
      record.errorMessage = nil;
      record.fileUri = destination.absoluteString;
      if (record.totalBytes == nil) record.totalBytes = @(record.bytesDownloaded);
      record.updatedAt = [self now];
      [self persistRecordQuietly:record];
      [self emit:@"state" task:[self snapshot:record]];
    } else {
      record.nativeTask = nil;
      record.state = DMStateFailed;
      record.errorMessage = moveError.localizedDescription ?: @"Unable to save download";
      record.updatedAt = [self now];
      [self persistRecordQuietly:record];
      [self emit:@"state" task:[self snapshot:record]];
    }
  });
}

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didCompleteWithError:(nullable NSError *)error {
  dispatch_async(_queue, ^{
    DMDownloadRecord *record = self->_records[task.taskDescription];
    if (record == nil || record.nativeTask != task) return;
    if (record.persistProgress) {
      [self closeFile:record];
      record.nativeTask = nil;
      if (error != nil) {
        record.state = DMStateFailed;
        record.errorMessage = error.localizedDescription ?: @"Download failed";
        record.updatedAt = [self now];
        [self persistRecordQuietly:record];
        [self emit:@"state" task:[self snapshot:record]];
        return;
      }
      [self finishPersistentRecord:record];
      return;
    }
    if (error == nil) return;
    record.nativeTask = nil;
    NSData *resumeData = error.userInfo[NSURLSessionDownloadTaskResumeData];
    if ([resumeData isKindOfClass:NSData.class]) record.resumeData = resumeData;
    if ([record.state isEqualToString:DMStatePaused]
        || [record.state isEqualToString:DMStateCancelled]
        || [record.state isEqualToString:DMStateCompleted]) {
      return;
    }
    record.state = DMStateFailed;
    record.errorMessage = error.localizedDescription ?: @"Download failed";
    record.updatedAt = [self now];
    [self persistRecordQuietly:record];
    [self emit:@"state" task:[self snapshot:record]];
  });
}

#pragma mark - Helpers

- (nullable NSURLSessionTask *)newTaskForRecord:(DMDownloadRecord *)record
                                     resumeData:(nullable NSData *)resumeData
                                          error:(NSError **)error {
  if (record.persistProgress) {
    return [self newPersistentTaskForRecord:record error:error];
  }
  if (resumeData != nil) {
    NSURLSessionDownloadTask *task = [_session downloadTaskWithResumeData:resumeData];
    task.taskDescription = record.identifier;
    return task;
  }
  NSURL *url = [NSURL URLWithString:record.url];
  if (url == nil) {
    if (error != NULL) *error = [self error:@"Invalid download URL"];
    return nil;
  }
  NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
  request.HTTPMethod = @"GET";
  request.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
  for (NSString *name in record.headers) {
    [request setValue:record.headers[name] forHTTPHeaderField:name];
  }
  NSURLSessionDownloadTask *task = [_session downloadTaskWithRequest:request];
  task.taskDescription = record.identifier;
  return task;
}

- (nullable NSURLSessionDataTask *)newPersistentTaskForRecord:(DMDownloadRecord *)record
                                                        error:(NSError **)error {
  NSURL *url = [NSURL URLWithString:record.url];
  if (url == nil) {
    if (error != NULL) *error = [self error:@"Invalid download URL"];
    return nil;
  }
  NSURL *partial = [self partialURL:record error:error];
  if (partial == nil) return nil;
  NSNumber *partialSize = [self fileSizeAtURL:partial];
  int64_t offset = partialSize == nil ? 0 : partialSize.longLongValue;
  if (offset < 0 || offset > DMMaxSafeInteger) {
    if (error != NULL) *error = [self error:@"Partial download is too large"];
    return nil;
  }
  if (offset > 0 && record.rangeValidator.length == 0) {
    if (![[NSFileManager defaultManager] removeItemAtURL:partial error:error]) return nil;
    offset = 0;
    record.bytesDownloaded = 0;
    record.totalBytes = nil;
  }

  NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
  request.HTTPMethod = @"GET";
  request.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
  for (NSString *name in record.headers) {
    [request setValue:record.headers[name] forHTTPHeaderField:name];
  }
  [request setValue:@"identity" forHTTPHeaderField:@"Accept-Encoding"];
  if (offset > 0) {
    [request setValue:[NSString stringWithFormat:@"bytes=%lld-", offset]
        forHTTPHeaderField:@"Range"];
    [request setValue:record.rangeValidator forHTTPHeaderField:@"If-Range"];
  }
  record.requestedOffset = offset;
  record.bytesDownloaded = offset;
  NSURLSessionDataTask *task = [_session dataTaskWithRequest:request];
  task.taskDescription = record.identifier;
  return task;
}

- (void)closeFile:(DMDownloadRecord *)record {
  NSFileHandle *handle = record.fileHandle;
  record.fileHandle = nil;
  if (handle == nil) return;
  @try {
    [handle synchronizeFile];
    [handle closeFile];
  } @catch (__unused NSException *exception) {
  }
}

- (void)finishPersistentRecord:(DMDownloadRecord *)record {
  [self closeFile:record];
  NSError *fileError;
  NSURL *partial = [self partialURL:record error:&fileError];
  NSNumber *partialSize = partial == nil ? nil : [self fileSizeAtURL:partial];
  if (partial == nil || partialSize == nil) {
    [self failPersistentRecord:record
                       message:fileError.localizedDescription ?: @"Partial download is missing"];
    return;
  }
  int64_t downloaded = partialSize.longLongValue;
  if (record.totalBytes != nil && record.totalBytes.longLongValue != downloaded) {
    [self failPersistentRecord:record
                       message:@"Downloaded byte count did not match Content-Length"];
    return;
  }
  NSURL *destination = [self destinationURL:record error:&fileError];
  NSFileManager *manager = NSFileManager.defaultManager;
  if (destination != nil && [manager fileExistsAtPath:destination.path]) {
    [manager removeItemAtURL:destination error:&fileError];
  }
  if (destination == nil || fileError != nil
      || ![manager moveItemAtURL:partial toURL:destination error:&fileError]) {
    [self failPersistentRecord:record
                       message:fileError.localizedDescription ?: @"Unable to save download"];
    return;
  }
  record.nativeTask = nil;
  record.state = DMStateCompleted;
  record.bytesDownloaded = downloaded;
  record.totalBytes = @(downloaded);
  record.fileUri = destination.absoluteString;
  record.errorMessage = nil;
  record.updatedAt = [self now];
  [self persistRecordQuietly:record];
  [self emit:@"state" task:[self snapshot:record]];
}

- (void)failPersistentRecord:(DMDownloadRecord *)record message:(NSString *)message {
  NSURLSessionTask *task = record.nativeTask;
  record.nativeTask = nil;
  [self closeFile:record];
  record.state = DMStateFailed;
  record.fileUri = nil;
  record.errorMessage = message.length > 0 ? message : @"Download failed";
  record.updatedAt = [self now];
  [self persistRecordQuietly:record];
  [self emit:@"state" task:[self snapshot:record]];
  [task cancel];
}

- (nullable NSNumber *)contentRangeStart:(nullable NSString *)value {
  if (![value isKindOfClass:NSString.class] || ![value hasPrefix:@"bytes "]) return nil;
  NSScanner *scanner = [NSScanner scannerWithString:value];
  long long start;
  if (![scanner scanString:@"bytes " intoString:nil]
      || ![scanner scanLongLong:&start]
      || start < 0
      || ![scanner scanString:@"-" intoString:nil]) {
    return nil;
  }
  return @(start);
}

- (nullable NSNumber *)contentRangeTotal:(nullable NSString *)value {
  if (![value isKindOfClass:NSString.class]) return nil;
  NSRange slash = [value rangeOfString:@"/" options:NSBackwardsSearch];
  if (slash.location == NSNotFound || NSMaxRange(slash) >= value.length) return nil;
  NSString *suffix = [value substringFromIndex:NSMaxRange(slash)];
  if ([suffix isEqualToString:@"*"]) return nil;
  NSScanner *scanner = [NSScanner scannerWithString:suffix];
  long long total;
  if (![scanner scanLongLong:&total] || total < 0 || !scanner.isAtEnd) return nil;
  return @(total);
}

- (nullable NSString *)responseValidator:(NSHTTPURLResponse *)response {
  NSString *etag = [[response valueForHTTPHeaderField:@"ETag"]
      stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  if (etag.length > 0 && ![etag hasPrefix:@"W/"]) return etag;
  NSString *lastModified = [[response valueForHTTPHeaderField:@"Last-Modified"]
      stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  return lastModified.length > 0 ? lastModified : nil;
}

- (nullable DMDownloadRecord *)requireRecord:(NSString *)identifier
                                        error:(NSError **)error {
  DMDownloadRecord *record = _records[identifier];
  if (record == nil && error != NULL) *error = [self error:@"Unknown download task ID"];
  return record;
}

- (NSDictionary *)snapshot:(DMDownloadRecord *)record {
  return @{
    @"id" : record.identifier,
    @"url" : record.url,
    @"fileName" : record.fileName,
    @"state" : record.state,
    @"executionMode" : @"in-app",
    @"persistProgress" : @(record.persistProgress),
    @"bytesDownloaded" : @(record.bytesDownloaded),
    @"totalBytes" : record.totalBytes ?: NSNull.null,
    @"fileUri" : record.fileUri ?: NSNull.null,
    @"error" : record.errorMessage ?: NSNull.null,
    @"createdAt" : @(record.createdAt),
    @"updatedAt" : @(record.updatedAt),
  };
}

- (void)emit:(NSString *)type task:(NSDictionary *)task {
  NSArray<DownloadManagerModule *> *sinks = _sinks.allObjects;
  for (DownloadManagerModule *sink in sinks) {
    [sink emitDownloadEvent:type task:task];
  }
}

- (void)loadPersistedRecords {
  NSError *directoryError;
  NSURL *directory = [self persistenceDirectoryURL:&directoryError];
  if (directory == nil) return;
  NSArray<NSURL *> *files = [NSFileManager.defaultManager
      contentsOfDirectoryAtURL:directory
    includingPropertiesForKeys:nil
                       options:NSDirectoryEnumerationSkipsHiddenFiles
                         error:nil];
  for (NSURL *file in files) {
    if (![file.pathExtension isEqualToString:@"json"]) continue;
    NSError *loadError;
    NSData *data = [NSData dataWithContentsOfURL:file options:NSDataReadingMappedIfSafe
                                           error:&loadError];
    id value = data.length > 0 && data.length <= 1024 * 1024
        ? [NSJSONSerialization JSONObjectWithData:data options:0 error:&loadError]
        : nil;
    DMDownloadRecord *record = [value isKindOfClass:NSDictionary.class]
        ? [self recordFromPersistedDictionary:value error:&loadError]
        : nil;
    NSString *expectedName = record == nil
        ? nil
        : [record.identifier stringByAppendingPathExtension:@"json"];
    if (record == nil || ![file.lastPathComponent isEqualToString:expectedName]
        || _records[record.identifier] != nil) {
      [NSFileManager.defaultManager removeItemAtURL:file error:nil];
      continue;
    }
    _records[record.identifier] = record;
    [self persistRecordQuietly:record];
  }
}

- (BOOL)persistRecord:(DMDownloadRecord *)record error:(NSError **)error {
  if (!record.persistProgress) return YES;
  @try {
    [record.fileHandle synchronizeFile];
  } @catch (__unused NSException *exception) {
  }
  NSDictionary *value = @{
    @"version" : @(DMPersistenceVersion),
    @"id" : record.identifier,
    @"url" : record.url,
    @"fileName" : record.fileName,
    @"headers" : record.headers,
    @"progressIntervalMs" : @(record.progressIntervalMs),
    @"persistProgress" : @YES,
    @"state" : record.state,
    @"bytesDownloaded" : @(record.bytesDownloaded),
    @"totalBytes" : record.totalBytes ?: NSNull.null,
    @"error" : record.errorMessage ?: NSNull.null,
    @"rangeValidator" : record.rangeValidator ?: NSNull.null,
    @"createdAt" : @(record.createdAt),
    @"updatedAt" : @(record.updatedAt),
  };
  NSData *data = [NSJSONSerialization dataWithJSONObject:value options:0 error:error];
  if (data == nil) return NO;
  NSURL *destination = [self metadataURL:record error:error];
  return destination != nil
      && [data writeToURL:destination options:NSDataWritingAtomic error:error];
}

- (void)persistRecordQuietly:(DMDownloadRecord *)record {
  [self persistRecord:record error:nil];
}

- (BOOL)deletePersistedRecord:(DMDownloadRecord *)record error:(NSError **)error {
  if (!record.persistProgress) return YES;
  NSURL *url = [self metadataURL:record error:error];
  if (url == nil) return NO;
  if (![NSFileManager.defaultManager fileExistsAtPath:url.path]) return YES;
  return [NSFileManager.defaultManager removeItemAtURL:url error:error];
}

- (nullable DMDownloadRecord *)recordFromPersistedDictionary:(NSDictionary *)value
                                                        error:(NSError **)error {
  NSNumber *version = value[@"version"];
  NSNumber *persist = value[@"persistProgress"];
  NSString *identifier = value[@"id"];
  NSString *url = value[@"url"];
  NSString *fileName = value[@"fileName"];
  NSDictionary *headers = value[@"headers"];
  NSNumber *interval = value[@"progressIntervalMs"];
  NSString *state = value[@"state"];
  NSNumber *createdAt = value[@"createdAt"];
  NSNumber *updatedAt = value[@"updatedAt"];
  NSNumber *storedBytes = value[@"bytesDownloaded"];
  id storedTotal = value[@"totalBytes"];
  id storedError = value[@"error"];
  id storedValidator = value[@"rangeValidator"];
  if (![version isKindOfClass:NSNumber.class]
      || version.integerValue != DMPersistenceVersion
      || ![persist isKindOfClass:NSNumber.class] || !persist.boolValue
      || ![self isSafeIdentifier:identifier] || ![self isSafeURL:url]
      || ![self isSafeFileName:fileName] || ![self areSafeHeaders:headers]
      || ![interval isKindOfClass:NSNumber.class]
      || interval.integerValue < 100 || interval.integerValue > 10000
      || ![self isKnownState:state]
      || ![self isSafeInteger:createdAt] || ![self isSafeInteger:updatedAt]
      || ![self isSafeInteger:storedBytes]
      || (storedTotal != NSNull.null && ![self isSafeInteger:storedTotal])
      || (storedError != NSNull.null
          && (![storedError isKindOfClass:NSString.class]
              || [storedError length] > 4096))
      || (storedValidator != NSNull.null
          && (![storedValidator isKindOfClass:NSString.class]
              || [storedValidator length] == 0
              || [storedValidator length] > 8192
              || [storedValidator rangeOfCharacterFromSet:
                      NSCharacterSet.newlineCharacterSet].location != NSNotFound))) {
    if (error != NULL) *error = [self error:@"Invalid persisted download task"];
    return nil;
  }

  DMDownloadRecord *record = [[DMDownloadRecord alloc] init];
  record.identifier = identifier;
  record.url = url;
  record.fileName = fileName;
  record.headers = headers;
  record.progressIntervalMs = interval.integerValue;
  record.persistProgress = YES;
  record.state = state;
  record.createdAt = createdAt.longLongValue;
  record.updatedAt = MAX(record.createdAt, updatedAt.longLongValue);
  record.bytesDownloaded = storedBytes.longLongValue;
  record.totalBytes = storedTotal == NSNull.null ? nil : storedTotal;
  record.errorMessage = storedError == NSNull.null ? nil : storedError;
  record.rangeValidator = storedValidator == NSNull.null ? nil : storedValidator;

  NSError *fileError;
  NSURL *partial = [self partialURL:record error:&fileError];
  NSURL *destination = [self destinationURL:record error:&fileError];
  NSNumber *partialSize = partial == nil ? nil : [self fileSizeAtURL:partial];
  NSNumber *destinationSize = destination == nil ? nil : [self fileSizeAtURL:destination];
  if ([record.state isEqualToString:DMStateCompleted]) {
    if (destinationSize != nil && destinationSize.longLongValue <= DMMaxSafeInteger) {
      record.bytesDownloaded = destinationSize.longLongValue;
      record.totalBytes = destinationSize;
      record.fileUri = destination.absoluteString;
      record.errorMessage = nil;
    } else {
      record.state = DMStateFailed;
      record.bytesDownloaded = partialSize.longLongValue;
      record.totalBytes = nil;
      record.fileUri = nil;
      record.errorMessage = @"Downloaded file is missing";
      record.updatedAt = [self now];
    }
  } else if ([record.state isEqualToString:DMStateCancelled]) {
    if (partial != nil) [NSFileManager.defaultManager removeItemAtURL:partial error:nil];
    record.bytesDownloaded = 0;
    record.fileUri = nil;
  } else {
    int64_t length = partialSize == nil ? 0 : partialSize.longLongValue;
    if (length < 0 || length > DMMaxSafeInteger) {
      if (error != NULL) *error = [self error:@"Persisted partial file is too large"];
      return nil;
    }
    record.bytesDownloaded = length;
    record.fileUri = nil;
    if ([record.state isEqualToString:DMStateQueued]
        || [record.state isEqualToString:DMStateRunning]) {
      record.state = DMStatePaused;
      record.errorMessage = nil;
      record.updatedAt = [self now];
    }
  }
  if (record.totalBytes != nil
      && record.totalBytes.longLongValue < record.bytesDownloaded) {
    record.totalBytes = nil;
  }
  return record;
}

- (BOOL)isSafeIdentifier:(id)value {
  if (![value isKindOfClass:NSString.class]
      || [value length] == 0 || [value length] > 128) return NO;
  NSCharacterSet *allowed = [NSCharacterSet
      characterSetWithCharactersInString:
          @"0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz._-"];
  return [value rangeOfCharacterFromSet:allowed.invertedSet].location == NSNotFound;
}

- (BOOL)isSafeURL:(id)value {
  if (![value isKindOfClass:NSString.class] || [value length] > 8192) return NO;
  NSURL *url = [NSURL URLWithString:value];
  NSString *scheme = url.scheme.lowercaseString;
  return url.host.length > 0
      && ([scheme isEqualToString:@"https"] || [scheme isEqualToString:@"http"]);
}

- (BOOL)isSafeFileName:(id)value {
  if (![value isKindOfClass:NSString.class]
      || [value length] == 0 || [value length] > 128
      || [value isEqualToString:@"."] || [value isEqualToString:@".."]
      || ![value isEqualToString:[value stringByTrimmingCharactersInSet:
                                      NSCharacterSet.whitespaceAndNewlineCharacterSet]]
      || [value rangeOfString:@"/"].location != NSNotFound
      || [value rangeOfString:@"\\"].location != NSNotFound
      || [value rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location
          != NSNotFound) {
    return NO;
  }
  return YES;
}

- (BOOL)areSafeHeaders:(id)value {
  if (![value isKindOfClass:NSDictionary.class] || [value count] > 64) return NO;
  NSCharacterSet *tokenCharacters = [NSCharacterSet
      characterSetWithCharactersInString:
          @"!#$%&'*+-.^_`|~0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"];
  NSSet<NSString *> *reserved = [NSSet setWithArray:@[
    @"accept-encoding", @"connection", @"content-length", @"host",
    @"if-range", @"range", @"transfer-encoding",
  ]];
  for (id name in value) {
    id headerValue = [(NSDictionary *)value objectForKey:name];
    if (![name isKindOfClass:NSString.class]
        || ![headerValue isKindOfClass:NSString.class]
        || [name length] == 0
        || [name rangeOfCharacterFromSet:tokenCharacters.invertedSet].location != NSNotFound
        || [reserved containsObject:[name lowercaseString]]
        || [headerValue length] > 8192
        || [headerValue rangeOfCharacterFromSet:NSCharacterSet.newlineCharacterSet].location
            != NSNotFound) {
      return NO;
    }
  }
  return YES;
}

- (BOOL)isKnownState:(id)value {
  return [value isKindOfClass:NSString.class]
      && [@[ DMStateQueued, DMStateRunning, DMStatePaused, DMStateCompleted,
             DMStateFailed, DMStateCancelled ] containsObject:value];
}

- (BOOL)isSafeInteger:(id)value {
  if (![value isKindOfClass:NSNumber.class]) return NO;
  int64_t integer = [value longLongValue];
  return integer >= 0 && integer <= DMMaxSafeInteger
      && [value doubleValue] == (double)integer;
}

- (nullable NSURL *)persistenceDirectoryURL:(NSError **)error {
  NSFileManager *manager = NSFileManager.defaultManager;
  NSURL *applicationSupport = [manager URLForDirectory:NSApplicationSupportDirectory
                                              inDomain:NSUserDomainMask
                                     appropriateForURL:nil
                                                create:YES
                                                 error:error];
  if (applicationSupport == nil) return nil;
  NSURL *directory = [[[applicationSupport
      URLByAppendingPathComponent:@"LynxFiles" isDirectory:YES]
      URLByAppendingPathComponent:@"download-manager" isDirectory:YES]
      URLByAppendingPathComponent:@"tasks" isDirectory:YES];
  if (![manager createDirectoryAtURL:directory
          withIntermediateDirectories:YES
                           attributes:nil
                                error:error]) {
    return nil;
  }
  [directory setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];
  return directory;
}

- (nullable NSURL *)metadataURL:(DMDownloadRecord *)record error:(NSError **)error {
  NSURL *directory = [self persistenceDirectoryURL:error];
  if (directory == nil) return nil;
  NSString *name = [record.identifier stringByAppendingPathExtension:@"json"];
  return [directory URLByAppendingPathComponent:name isDirectory:NO];
}

- (nullable NSURL *)partialURL:(DMDownloadRecord *)record error:(NSError **)error {
  NSURL *destination = [self destinationURL:record error:error];
  return destination == nil
      ? nil
      : [NSURL fileURLWithPath:[destination.path stringByAppendingString:@".part"]];
}

- (nullable NSNumber *)fileSizeAtURL:(NSURL *)url {
  NSDictionary *attributes = [NSFileManager.defaultManager
      attributesOfItemAtPath:url.path
                       error:nil];
  NSNumber *size = attributes[NSFileSize];
  return [size isKindOfClass:NSNumber.class] ? size : nil;
}

- (nullable NSURL *)destinationURL:(DMDownloadRecord *)record error:(NSError **)error {
  NSFileManager *manager = [NSFileManager defaultManager];
  NSURL *cache = [manager URLForDirectory:NSCachesDirectory
                                 inDomain:NSUserDomainMask
                        appropriateForURL:nil
                                   create:YES
                                    error:error];
  if (cache == nil) return nil;
  NSURL *directory = [[cache URLByAppendingPathComponent:@"LynxFiles" isDirectory:YES]
      URLByAppendingPathComponent:@"downloads" isDirectory:YES];
  if (![manager createDirectoryAtURL:directory
          withIntermediateDirectories:YES
                           attributes:nil
                                error:error]) {
    return nil;
  }
  NSString *name = [NSString stringWithFormat:@"%@-%@", record.identifier, record.fileName];
  return [directory URLByAppendingPathComponent:name isDirectory:NO];
}

- (int64_t)now {
  return (int64_t)(NSDate.date.timeIntervalSince1970 * 1000.0);
}

- (NSError *)error:(NSString *)message {
  return [NSError errorWithDomain:DMErrorDomain
                             code:1
                         userInfo:@{NSLocalizedDescriptionKey : message}];
}

@end

static NSString *DMResult(id _Nullable value, NSString *error) {
  NSDictionary *envelope = @{
    @"value" : value ?: NSNull.null,
    @"error" : error ?: @"",
  };
  NSData *data = [NSJSONSerialization dataWithJSONObject:envelope options:0 error:nil];
  if (data == nil) {
    return @"{\"value\":null,\"error\":\"Unable to encode DownloadManager result\"}";
  }
  return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

// Exported to Lynx as `DownloadManager`.
@LynxNativeModule("DownloadManager")
@implementation DownloadManagerModule {
  LynxContext *_context;
  BOOL _destroyed;
}

+ (NSString *)name {
  return @"DownloadManager";
}

+ (NSDictionary<NSString *, NSString *> *)methodLookup {
  return @{
    @"getCapabilities" : NSStringFromSelector(@selector(getCapabilities:)),
    @"enqueue" : NSStringFromSelector(@selector(enqueue:callback:)),
    @"pause" : NSStringFromSelector(@selector(pause:callback:)),
    @"resume" : NSStringFromSelector(@selector(resume:callback:)),
    @"cancel" : NSStringFromSelector(@selector(cancel:callback:)),
    @"remove" : NSStringFromSelector(@selector(remove:deleteFile:callback:)),
    @"getTask" : NSStringFromSelector(@selector(getTask:callback:)),
    @"listTasks" : NSStringFromSelector(@selector(listTasks:)),
  };
}

- (instancetype)initWithLynxContext:(LynxContext *)context {
  self = [super init];
  if (self) {
    _context = context;
    [[DMDownloadStore shared] addSink:self];
  }
  return self;
}

- (void)destroy {
  _destroyed = YES;
  [[DMDownloadStore shared] removeSink:self];
  _context = nil;
}

- (void)getCapabilities:(LynxCallbackBlock)callback {
  callback(DMResult(@{
    @"platform" : @"ios",
    @"executionModes" : @[ @"in-app" ],
    @"byteRangeResume" : @YES,
    @"processRestartRecovery" : @YES,
  }, @""));
}

- (void)enqueue:(NSDictionary *)options callback:(LynxCallbackBlock)callback {
  NSString *validationError = [self validateOptions:options];
  if (validationError.length > 0) {
    callback(DMResult(nil, validationError));
    return;
  }
  NSError *error;
  NSDictionary *task = [[DMDownloadStore shared] enqueue:options error:&error];
  callback(DMResult(task, error.localizedDescription ?: @""));
}

- (void)pause:(NSString *)identifier callback:(LynxCallbackBlock)callback {
  [self taskCommand:identifier callback:callback operation:@selector(pause:error:)];
}

- (void)resume:(NSString *)identifier callback:(LynxCallbackBlock)callback {
  [self taskCommand:identifier callback:callback operation:@selector(resume:error:)];
}

- (void)cancel:(NSString *)identifier callback:(LynxCallbackBlock)callback {
  [self taskCommand:identifier callback:callback operation:@selector(cancel:error:)];
}

- (void)remove:(NSString *)identifier
      deleteFile:(BOOL)deleteFile
        callback:(LynxCallbackBlock)callback {
  NSString *validationError = [self validateIdentifier:identifier];
  if (validationError.length > 0) {
    callback(DMResult(nil, validationError));
    return;
  }
  NSError *error;
  BOOL success = [[DMDownloadStore shared] remove:identifier
                                       deleteFile:deleteFile
                                            error:&error];
  callback(DMResult(nil, success ? @"" : error.localizedDescription));
}

- (void)getTask:(NSString *)identifier callback:(LynxCallbackBlock)callback {
  NSString *validationError = [self validateIdentifier:identifier];
  if (validationError.length > 0) {
    callback(DMResult(nil, validationError));
    return;
  }
  callback(DMResult([[DMDownloadStore shared] task:identifier], @""));
}

- (void)listTasks:(LynxCallbackBlock)callback {
  callback(DMResult([[DMDownloadStore shared] tasks], @""));
}

- (void)emitDownloadEvent:(NSString *)type task:(NSDictionary *)task {
  dispatch_async(dispatch_get_main_queue(), ^{
    if (self->_destroyed || self->_context == nil) return;
    [self->_context sendGlobalEvent:DMEventName
                        withParams:@[ @{ @"type" : type, @"task" : task } ]];
  });
}

- (void)taskCommand:(NSString *)identifier
           callback:(LynxCallbackBlock)callback
          operation:(SEL)operation {
  NSString *validationError = [self validateIdentifier:identifier];
  if (validationError.length > 0) {
    callback(DMResult(nil, validationError));
    return;
  }
  NSError *error;
  NSDictionary *task;
  DMDownloadStore *store = [DMDownloadStore shared];
  if (operation == @selector(pause:error:)) task = [store pause:identifier error:&error];
  else if (operation == @selector(resume:error:)) task = [store resume:identifier error:&error];
  else task = [store cancel:identifier error:&error];
  callback(DMResult(task, error.localizedDescription ?: @""));
}

- (NSString *)validateOptions:(NSDictionary *)options {
  if (![options isKindOfClass:NSDictionary.class]) return @"Download options are required";
  NSString *identifierError = [self validateIdentifier:options[@"id"]];
  if (identifierError.length > 0) return identifierError;
  NSString *urlValue = options[@"url"];
  NSURL *url = [urlValue isKindOfClass:NSString.class]
      ? [NSURL URLWithString:urlValue]
      : nil;
  NSString *scheme = url.scheme.lowercaseString;
  BOOL allowed = [scheme isEqualToString:@"https"];
#if DEBUG
  allowed = allowed || [scheme isEqualToString:@"http"];
#endif
  if (!allowed || url.host.length == 0 || urlValue.length > 8192) {
    return @"Download URL must use HTTPS (HTTP is Debug-only)";
  }
  NSString *fileName = options[@"fileName"];
  if (![fileName isKindOfClass:NSString.class]
      || fileName.length == 0 || fileName.length > 128
      || [fileName isEqualToString:@"."] || [fileName isEqualToString:@".."]
      || ![fileName isEqualToString:[fileName stringByTrimmingCharactersInSet:
                                             NSCharacterSet.whitespaceAndNewlineCharacterSet]]
      || [fileName rangeOfString:@"/"].location != NSNotFound
      || [fileName rangeOfString:@"\\"].location != NSNotFound
      || [fileName rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location
          != NSNotFound) {
    return @"Invalid download fileName";
  }
  NSNumber *interval = options[@"progressIntervalMs"];
  if (![interval isKindOfClass:NSNumber.class]
      || interval.integerValue < 100 || interval.integerValue > 10000) {
    return @"progressIntervalMs must be between 100 and 10000";
  }
  if (![options[@"persistProgress"] isKindOfClass:NSNumber.class]) {
    return @"persistProgress must be a boolean";
  }
  NSDictionary *headers = options[@"headers"];
  if (![headers isKindOfClass:NSDictionary.class] || headers.count > 64) {
    return @"Invalid download headers";
  }
  NSCharacterSet *tokenCharacters = [NSCharacterSet
      characterSetWithCharactersInString:
          @"!#$%&'*+-.^_`|~0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"];
  NSSet<NSString *> *reserved = [NSSet setWithArray:@[
    @"accept-encoding", @"connection", @"content-length", @"host",
    @"if-range", @"range", @"transfer-encoding",
  ]];
  for (id name in headers) {
    id value = headers[name];
    if (![name isKindOfClass:NSString.class] || ![value isKindOfClass:NSString.class]
        || [name rangeOfCharacterFromSet:tokenCharacters.invertedSet].location != NSNotFound
        || [reserved containsObject:[name lowercaseString]]
        || [value length] > 8192
        || [value rangeOfCharacterFromSet:NSCharacterSet.newlineCharacterSet].location
            != NSNotFound) {
      return @"Invalid download header";
    }
  }
  return @"";
}

- (NSString *)validateIdentifier:(id)value {
  if (![value isKindOfClass:NSString.class]
      || [value length] == 0 || [value length] > 128) {
    return @"Invalid download task ID";
  }
  NSCharacterSet *allowed = [NSCharacterSet
      characterSetWithCharactersInString:
          @"0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz._-"];
  return [value rangeOfCharacterFromSet:allowed.invertedSet].location == NSNotFound
      ? @""
      : @"Invalid download task ID";
}

@end
