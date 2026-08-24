#import "CameraPhotoUtils.h"

static NSString *const LynxCameraErrorDomain = @"LynxCamera";

NSDictionary<NSString *, id> *_Nullable
LynxCameraWriteJPEG(UIImage *image,
                    CGFloat quality,
                    BOOL mirrorHorizontally,
                    NSError **error) {
  if (image.size.width <= 0 || image.size.height <= 0) {
    if (error != NULL) {
      *error = [NSError errorWithDomain:LynxCameraErrorDomain
                                   code:1
                               userInfo:@{NSLocalizedDescriptionKey :
                                            @"The camera returned an invalid image"}];
    }
    return nil;
  }

  UIGraphicsBeginImageContextWithOptions(image.size, YES, image.scale);
  CGContextRef context = UIGraphicsGetCurrentContext();
  if (context == NULL) {
    UIGraphicsEndImageContext();
    if (error != NULL) {
      *error = [NSError errorWithDomain:LynxCameraErrorDomain
                                   code:2
                               userInfo:@{NSLocalizedDescriptionKey :
                                            @"Unable to create a camera image context"}];
    }
    return nil;
  }
  if (mirrorHorizontally) {
    CGContextTranslateCTM(context, image.size.width, 0);
    CGContextScaleCTM(context, -1, 1);
  }
  [image drawInRect:(CGRect){CGPointZero, image.size}];
  UIImage *normalized = UIGraphicsGetImageFromCurrentImageContext();
  UIGraphicsEndImageContext();
  if (normalized == nil || normalized.CGImage == NULL) {
    if (error != NULL) {
      *error = [NSError errorWithDomain:LynxCameraErrorDomain
                                   code:3
                               userInfo:@{NSLocalizedDescriptionKey :
                                            @"Unable to normalize the captured image"}];
    }
    return nil;
  }

  NSData *data = UIImageJPEGRepresentation(
      normalized, MIN(1.0, MAX(0.01, quality)));
  if (data == nil) {
    if (error != NULL) {
      *error = [NSError errorWithDomain:LynxCameraErrorDomain
                                   code:4
                               userInfo:@{NSLocalizedDescriptionKey :
                                            @"Unable to encode the captured image"}];
    }
    return nil;
  }

  NSURL *base = [NSFileManager.defaultManager
      URLForDirectory:NSCachesDirectory
             inDomain:NSUserDomainMask
    appropriateForURL:nil
               create:YES
                error:error];
  if (base == nil) {
    return nil;
  }
  NSURL *directory = [base URLByAppendingPathComponent:@"LynxCamera"
                                           isDirectory:YES];
  if (![NSFileManager.defaultManager
          createDirectoryAtURL:directory
   withIntermediateDirectories:YES
                    attributes:nil
                         error:error]) {
    return nil;
  }
  NSURL *destination = [directory URLByAppendingPathComponent:
      [NSString stringWithFormat:@"%@.jpg", NSUUID.UUID.UUIDString]];
  if (![data writeToURL:destination options:NSDataWritingAtomic error:error]) {
    return nil;
  }

  return @{
    @"uri" : destination.absoluteString,
    @"width" : @(CGImageGetWidth(normalized.CGImage)),
    @"height" : @(CGImageGetHeight(normalized.CGImage)),
    @"mimeType" : @"image/jpeg",
    @"sizeBytes" : @(data.length),
  };
}
