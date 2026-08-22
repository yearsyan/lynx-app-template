#import "ImageToolingModule.h"

#import <ImageIO/CGImageProperties.h>
#import <ImageIO/ImageIO.h>
#import <UIKit/UIKit.h>

static const NSInteger ImageToolingMaxPixels = 50000000;
static const NSInteger ImageToolingMaxDimension = 16384;
static const NSInteger ImageToolingMaxImages = 16;

@LynxNativeModule("ImageTooling")
@implementation ImageToolingModule {
  dispatch_queue_t _workQueue;
}

+ (NSString *)name {
  return @"ImageTooling";
}

+ (NSDictionary<NSString *, NSString *> *)methodLookup {
  return @{
    @"info" : NSStringFromSelector(@selector(info:callback:)),
    @"compress" : NSStringFromSelector(@selector(compress:callback:)),
    @"crop" : NSStringFromSelector(@selector(crop:callback:)),
    @"compose" : NSStringFromSelector(@selector(compose:callback:)),
    @"readExif" : NSStringFromSelector(@selector(readExif:callback:)),
    @"writeExif" : NSStringFromSelector(@selector(writeExif:callback:)),
    @"removeExif" : NSStringFromSelector(@selector(removeExif:callback:)),
  };
}

- (instancetype)initWithLynxContext:(LynxContext *)context {
  self = [super init];
  if (self) {
    _workQueue = dispatch_queue_create(
        "com.lynxapp.autolink.imagetooling.work", DISPATCH_QUEUE_SERIAL);
  }
  return self;
}

#pragma mark - Module methods

- (void)info:(NSString *)uriString callback:(LynxCallbackBlock)callback {
  NSURL *url = [self imageURL:uriString];
  if (url == nil) {
    callback([self errorResult:@"ImageTooling supports file:// image URIs on iOS"]);
    return;
  }
  dispatch_async(_workQueue, ^{
    NSString *error = nil;
    NSDictionary *info = [self sourceInfoAtURL:url error:&error];
    callback(info != nil ? [self valueResult:info] : [self errorResult:error]);
  });
}

- (void)compress:(NSDictionary *)options callback:(LynxCallbackBlock)callback {
  if (![options isKindOfClass:NSDictionary.class]) {
    callback([self errorResult:@"ImageTooling compress requires options"]);
    return;
  }
  dispatch_async(_workQueue, ^{
    callback([self compressOptions:options suffix:@"compressed"]);
  });
}

- (void)crop:(NSDictionary *)options callback:(LynxCallbackBlock)callback {
  if (![options isKindOfClass:NSDictionary.class]) {
    callback([self errorResult:@"ImageTooling crop requires options"]);
    return;
  }
  dispatch_async(_workQueue, ^{
    callback([self cropOptions:options]);
  });
}

- (void)compose:(NSDictionary *)options callback:(LynxCallbackBlock)callback {
  if (![options isKindOfClass:NSDictionary.class]) {
    callback([self errorResult:@"ImageTooling compose requires options"]);
    return;
  }
  dispatch_async(_workQueue, ^{
    callback([self composeOptions:options]);
  });
}

- (void)readExif:(NSString *)uriString callback:(LynxCallbackBlock)callback {
  NSURL *url = [self imageURL:uriString];
  if (url == nil) {
    callback([self errorResult:@"ImageTooling supports file:// image URIs on iOS"]);
    return;
  }
  dispatch_async(_workQueue, ^{
    callback([self readExifAtURL:url]);
  });
}

- (void)writeExif:(NSDictionary *)options callback:(LynxCallbackBlock)callback {
  if (![options isKindOfClass:NSDictionary.class]) {
    callback([self errorResult:@"ImageTooling writeExif requires options"]);
    return;
  }
  dispatch_async(_workQueue, ^{
    callback([self writeExifOptions:options]);
  });
}

- (void)removeExif:(NSDictionary *)options callback:(LynxCallbackBlock)callback {
  if (![options isKindOfClass:NSDictionary.class]) {
    callback([self errorResult:@"ImageTooling removeExif requires options"]);
    return;
  }
  dispatch_async(_workQueue, ^{
    NSMutableDictionary *normalized = [options mutableCopy];
    if (normalized[@"quality"] == nil) {
      normalized[@"quality"] = @100;
    }
    NSURL *url = [self imageURL:normalized[@"uri"]];
    if (url == nil) {
      callback([self errorResult:@"ImageTooling supports file:// image URIs on iOS"]);
      return;
    }
    NSString *error = nil;
    NSDictionary *info = [self sourceInfoAtURL:url error:&error];
    if (info == nil) {
      callback([self errorResult:error]);
      return;
    }
    if (normalized[@"format"] == nil || normalized[@"format"] == NSNull.null) {
      normalized[@"format"] = [info[@"mimeType"] isEqual:@"image/png"] ? @"png" : @"jpeg";
    }
    callback([self compressOptions:normalized suffix:@"exif-removed"]);
  });
}

#pragma mark - Image transforms

- (NSString *)compressOptions:(NSDictionary *)options suffix:(NSString *)suffix {
  NSURL *url = [self imageURL:options[@"uri"]];
  if (url == nil) {
    return [self errorResult:@"ImageTooling supports file:// image URIs on iOS"];
  }
  NSString *error = nil;
  NSDictionary *info = [self sourceInfoAtURL:url error:&error];
  if (info == nil) {
    return [self errorResult:error];
  }
  if (![self validateSourceInfo:info error:&error]) {
    return [self errorResult:error];
  }
  BOOL jpeg = NO;
  if (![self parseFormat:options[@"format"] defaultJPEG:YES jpeg:&jpeg error:&error]) {
    return [self errorResult:error];
  }
  NSNumber *maxWidth = [self positiveNumber:options[@"maxWidth"]];
  NSNumber *maxHeight = [self positiveNumber:options[@"maxHeight"]];
  CGSize displaySize = [self displaySize:info];
  CGFloat scale = [self fitScaleForSize:displaySize maxWidth:maxWidth maxHeight:maxHeight];
  CGSize targetSize = [self scaledSize:displaySize scale:scale];
  if (![self validateOutputSize:targetSize error:&error]) {
    return [self errorResult:error];
  }
  UIImage *image = [self decodedImageAtURL:url targetSize:targetSize error:&error];
  if (image == nil) {
    return [self errorResult:error];
  }
  NSInteger quality = [self quality:options[@"quality"] fallback:80];
  NSDictionary *value = [self writeImage:image jpeg:jpeg quality:quality suffix:suffix error:&error];
  return value != nil ? [self valueResult:value] : [self errorResult:error];
}

- (NSString *)cropOptions:(NSDictionary *)options {
  NSURL *url = [self imageURL:options[@"uri"]];
  if (url == nil) {
    return [self errorResult:@"ImageTooling supports file:// image URIs on iOS"];
  }
  NSString *error = nil;
  NSDictionary *info = [self sourceInfoAtURL:url error:&error];
  if (info == nil || ![self validateSourceInfo:info error:&error]) {
    return [self errorResult:error];
  }
  NSInteger x = [self nonNegativeInteger:options[@"x"] fallback:-1];
  NSInteger y = [self nonNegativeInteger:options[@"y"] fallback:-1];
  NSInteger width = [self positiveInteger:options[@"width"] fallback:-1];
  NSInteger height = [self positiveInteger:options[@"height"] fallback:-1];
  CGSize displaySize = [self displaySize:info];
  if (x < 0 || y < 0 || width < 1 || height < 1
      || x + width > (NSInteger)displaySize.width
      || y + height > (NSInteger)displaySize.height) {
    return [self errorResult:@"ImageTooling crop rectangle is outside the oriented image bounds"];
  }
  BOOL jpeg = NO;
  if (![self parseFormat:options[@"format"] defaultJPEG:YES jpeg:&jpeg error:&error]) {
    return [self errorResult:error];
  }
  CGSize cropSize = CGSizeMake(width, height);
  CGFloat scale = [self fitScaleForSize:cropSize
                               maxWidth:[self positiveNumber:options[@"maxWidth"]]
                              maxHeight:[self positiveNumber:options[@"maxHeight"]]];
  CGSize outputSize = [self scaledSize:cropSize scale:scale];
  if (![self validateOutputSize:outputSize error:&error]) {
    return [self errorResult:error];
  }
  CGSize decodedSize = [self scaledSize:displaySize scale:scale];
  UIImage *upright = [self decodedImageAtURL:url targetSize:decodedSize error:&error];
  if (upright == nil) {
    return [self errorResult:error];
  }
  NSInteger left = MIN(
      MAX(0, (NSInteger)lround(x * scale)),
      MAX(0, (NSInteger)decodedSize.width - (NSInteger)outputSize.width));
  NSInteger top = MIN(
      MAX(0, (NSInteger)lround(y * scale)),
      MAX(0, (NSInteger)decodedSize.height - (NSInteger)outputSize.height));
  CGRect cropRect = CGRectMake(left, top, outputSize.width, outputSize.height);
  CGImageRef croppedRef = CGImageCreateWithImageInRect(upright.CGImage, cropRect);
  if (croppedRef == nil) {
    return [self errorResult:@"ImageTooling failed to crop the image"];
  }
  UIImage *cropped = [UIImage imageWithCGImage:croppedRef scale:1 orientation:UIImageOrientationUp];
  CGImageRelease(croppedRef);
  NSDictionary *value = [self writeImage:cropped
                                    jpeg:jpeg
                                 quality:[self quality:options[@"quality"] fallback:80]
                                  suffix:@"cropped"
                                   error:&error];
  return value != nil ? [self valueResult:value] : [self errorResult:error];
}

- (NSString *)composeOptions:(NSDictionary *)options {
  NSArray *layers = [options[@"images"] isKindOfClass:NSArray.class] ? options[@"images"] : nil;
  if (layers.count < 1 || layers.count > ImageToolingMaxImages) {
    return [self errorResult:[NSString stringWithFormat:
        @"ImageTooling compose requires 1-%ld images", (long)ImageToolingMaxImages]];
  }
  NSString *layout = [options[@"layout"] isKindOfClass:NSString.class] ? options[@"layout"] : @"";
  if (![layout isEqual:@"horizontal"] && ![layout isEqual:@"vertical"]
      && ![layout isEqual:@"overlay"]) {
    return [self errorResult:@"Invalid ImageTooling compose layout"];
  }
  NSInteger spacing = [self nonNegativeInteger:options[@"spacing"] fallback:0];
  NSString *error = nil;
  NSMutableArray<NSDictionary *> *infos = [NSMutableArray arrayWithCapacity:layers.count];
  CGFloat rawWidth = 0;
  CGFloat rawHeight = 0;
  for (NSDictionary *layer in layers) {
    if (![layer isKindOfClass:NSDictionary.class]) {
      return [self errorResult:@"Invalid ImageTooling compose image"];
    }
    NSURL *url = [self imageURL:layer[@"uri"]];
    NSDictionary *info = url != nil ? [self sourceInfoAtURL:url error:&error] : nil;
    if (info == nil || ![self validateSourceInfo:info error:&error]) {
      return [self errorResult:error ?: @"ImageTooling cannot open a compose image"];
    }
    NSMutableDictionary *entry = [info mutableCopy];
    entry[@"url"] = url;
    [infos addObject:entry];
    CGSize size = [self displaySize:info];
    if ([layout isEqual:@"horizontal"]) {
      rawWidth += size.width;
      rawHeight = MAX(rawHeight, size.height);
    } else if ([layout isEqual:@"vertical"]) {
      rawWidth = MAX(rawWidth, size.width);
      rawHeight += size.height;
    } else {
      NSInteger x = [self nonNegativeInteger:layer[@"x"] fallback:0];
      NSInteger y = [self nonNegativeInteger:layer[@"y"] fallback:0];
      rawWidth = MAX(rawWidth, x + size.width);
      rawHeight = MAX(rawHeight, y + size.height);
    }
  }
  if (![layout isEqual:@"overlay"]) {
    CGFloat gaps = spacing * (layers.count - 1);
    if ([layout isEqual:@"horizontal"]) rawWidth += gaps;
    else rawHeight += gaps;
  }
  CGSize rawSize = CGSizeMake(rawWidth, rawHeight);
  CGFloat scale = [self fitScaleForSize:rawSize
                               maxWidth:[self positiveNumber:options[@"maxWidth"]]
                              maxHeight:[self positiveNumber:options[@"maxHeight"]]];
  CGSize outputSize = [self scaledSize:rawSize scale:scale];
  if (![self validateOutputSize:outputSize error:&error]) {
    return [self errorResult:error];
  }
  BOOL jpeg = NO;
  if (![self parseFormat:options[@"format"] defaultJPEG:YES jpeg:&jpeg error:&error]) {
    return [self errorResult:error];
  }

  UIGraphicsBeginImageContextWithOptions(outputSize, jpeg, 1.0);
  CGContextRef context = UIGraphicsGetCurrentContext();
  if (context == nil) {
    UIGraphicsEndImageContext();
    return [self errorResult:@"ImageTooling cannot create the composition canvas"];
  }
  if (jpeg) {
    [UIColor.whiteColor setFill];
    UIRectFill(CGRectMake(0, 0, outputSize.width, outputSize.height));
  }
  CGFloat cursor = 0;
  for (NSUInteger index = 0; index < infos.count; index++) {
    NSDictionary *info = infos[index];
    NSDictionary *layer = layers[index];
    CGSize size = [self scaledSize:[self displaySize:info] scale:scale];
    UIImage *image = [self decodedImageAtURL:info[@"url"] targetSize:size error:&error];
    if (image == nil) {
      UIGraphicsEndImageContext();
      return [self errorResult:error];
    }
    CGFloat left = 0;
    CGFloat top = 0;
    if ([layout isEqual:@"horizontal"]) {
      left = round(cursor * scale);
      cursor += [self displaySize:info].width + spacing;
    } else if ([layout isEqual:@"vertical"]) {
      top = round(cursor * scale);
      cursor += [self displaySize:info].height + spacing;
    } else {
      left = round([self nonNegativeInteger:layer[@"x"] fallback:0] * scale);
      top = round([self nonNegativeInteger:layer[@"y"] fallback:0] * scale);
    }
    CGFloat opacity = [layer[@"opacity"] respondsToSelector:@selector(doubleValue)]
        ? [layer[@"opacity"] doubleValue] : 1.0;
    CGContextSaveGState(context);
    CGContextSetAlpha(context, MAX(0, MIN(1, opacity)));
    [image drawInRect:CGRectMake(left, top, size.width, size.height)];
    CGContextRestoreGState(context);
  }
  UIImage *output = UIGraphicsGetImageFromCurrentImageContext();
  UIGraphicsEndImageContext();
  if (output == nil) {
    return [self errorResult:@"ImageTooling failed to compose images"];
  }
  NSDictionary *value = [self writeImage:output
                                    jpeg:jpeg
                                 quality:[self quality:options[@"quality"] fallback:80]
                                  suffix:@"composed"
                                   error:&error];
  return value != nil ? [self valueResult:value] : [self errorResult:error];
}

- (UIImage *)decodedImageAtURL:(NSURL *)url
                    targetSize:(CGSize)targetSize
                         error:(NSString **)error {
  CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, nil);
  if (source == nil) {
    if (error != nil) *error = @"ImageTooling cannot open the image URI";
    return nil;
  }
  CGFloat maxPixel = MAX(targetSize.width, targetSize.height);
  CGImageRef thumbnail = CGImageSourceCreateThumbnailAtIndex(
      source, 0, (__bridge CFDictionaryRef) @{
        (id)kCGImageSourceCreateThumbnailFromImageAlways : @YES,
        (id)kCGImageSourceCreateThumbnailWithTransform : @YES,
        (id)kCGImageSourceShouldCacheImmediately : @NO,
        (id)kCGImageSourceThumbnailMaxPixelSize : @(MAX(1, lround(maxPixel))),
      });
  CFRelease(source);
  if (thumbnail == nil) {
    if (error != nil) *error = @"ImageTooling cannot decode the image";
    return nil;
  }
  UIImage *decoded = [UIImage imageWithCGImage:thumbnail scale:1 orientation:UIImageOrientationUp];
  UIGraphicsBeginImageContextWithOptions(targetSize, NO, 1.0);
  [decoded drawInRect:CGRectMake(0, 0, targetSize.width, targetSize.height)];
  UIImage *fitted = UIGraphicsGetImageFromCurrentImageContext();
  UIGraphicsEndImageContext();
  CGImageRelease(thumbnail);
  if (fitted == nil && error != nil) {
    *error = @"ImageTooling cannot resize the image";
  }
  return fitted;
}

- (NSDictionary *)writeImage:(UIImage *)image
                         jpeg:(BOOL)jpeg
                      quality:(NSInteger)quality
                       suffix:(NSString *)suffix
                        error:(NSString **)error {
  UIImage *output = image;
  if (jpeg) {
    UIGraphicsBeginImageContextWithOptions(image.size, YES, 1.0);
    [UIColor.whiteColor setFill];
    UIRectFill(CGRectMake(0, 0, image.size.width, image.size.height));
    [image drawAtPoint:CGPointZero];
    output = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
  }
  NSData *data = jpeg
      ? UIImageJPEGRepresentation(output, MIN(1.0, MAX(0.01, quality / 100.0)))
      : UIImagePNGRepresentation(output);
  if (data == nil) {
    if (error != nil) *error = @"ImageTooling encoder failed";
    return nil;
  }
  NSURL *destination = [self cacheURLWithSuffix:suffix extension:jpeg ? @"jpg" : @"png" error:error];
  if (destination == nil || ![data writeToURL:destination atomically:YES]) {
    if (error != nil && *error == nil) *error = @"ImageTooling cannot write the cache file";
    return nil;
  }
  return @{
    @"uri" : destination.absoluteString,
    @"width" : @((NSInteger)image.size.width),
    @"height" : @((NSInteger)image.size.height),
    @"sizeBytes" : @(data.length),
  };
}

#pragma mark - EXIF

- (NSString *)readExifAtURL:(NSURL *)url {
  CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, nil);
  if (source == nil) {
    return [self errorResult:@"ImageTooling cannot open the image URI"];
  }
  NSDictionary *properties = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(
      source, 0, (__bridge CFDictionaryRef) @{(id)kCGImageSourceShouldCache : @NO}));
  CFRelease(source);
  if (properties == nil) {
    return [self errorResult:@"ImageTooling cannot read EXIF metadata"];
  }
  NSMutableDictionary *tags = [NSMutableDictionary dictionary];
  NSDictionary *definitions = [self exifDefinitions];
  [definitions enumerateKeysAndObjectsUsingBlock:^(NSString *name, NSDictionary *definition, BOOL *stop) {
    id containerKey = definition[@"container"];
    NSDictionary *container = containerKey == NSNull.null ? properties : properties[containerKey];
    id value = container[definition[@"key"]];
    NSString *string = [self exifString:value];
    if (string != nil) tags[name] = string;
  }];

  NSDictionary *gpsProperties = properties[(id)kCGImagePropertyGPSDictionary];
  id gps = NSNull.null;
  NSNumber *latitude = gpsProperties[(id)kCGImagePropertyGPSLatitude];
  NSNumber *longitude = gpsProperties[(id)kCGImagePropertyGPSLongitude];
  if ([latitude respondsToSelector:@selector(doubleValue)]
      && [longitude respondsToSelector:@selector(doubleValue)]) {
    double latitudeValue = latitude.doubleValue;
    double longitudeValue = longitude.doubleValue;
    if ([gpsProperties[(id)kCGImagePropertyGPSLatitudeRef] isEqual:@"S"]) latitudeValue *= -1;
    if ([gpsProperties[(id)kCGImagePropertyGPSLongitudeRef] isEqual:@"W"]) longitudeValue *= -1;
    NSMutableDictionary *gpsValue = [@{
      @"latitude" : @(latitudeValue),
      @"longitude" : @(longitudeValue),
    } mutableCopy];
    NSNumber *altitude = gpsProperties[(id)kCGImagePropertyGPSAltitude];
    if ([altitude respondsToSelector:@selector(doubleValue)]) {
      double altitudeValue = altitude.doubleValue;
      if ([gpsProperties[(id)kCGImagePropertyGPSAltitudeRef] integerValue] == 1) {
        altitudeValue *= -1;
      }
      gpsValue[@"altitude"] = @(altitudeValue);
    }
    gps = gpsValue;
  }
  return [self valueResult:@{ @"tags" : tags, @"gps" : gps }];
}

- (NSString *)writeExifOptions:(NSDictionary *)options {
  NSURL *url = [self imageURL:options[@"uri"]];
  if (url == nil) {
    return [self errorResult:@"ImageTooling supports file:// image URIs on iOS"];
  }
  CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, nil);
  if (source == nil) {
    return [self errorResult:@"ImageTooling cannot open the image URI"];
  }
  CFStringRef sourceType = CGImageSourceGetType(source);
  if (sourceType == nil) {
    CFRelease(source);
    return [self errorResult:@"ImageTooling cannot determine the source format"];
  }
  NSDictionary *sourceProperties = CFBridgingRelease(
      CGImageSourceCopyPropertiesAtIndex(source, 0, nil));
  NSMutableDictionary *properties = [sourceProperties mutableCopy] ?: [NSMutableDictionary dictionary];
  NSMutableDictionary *tiff = [properties[(id)kCGImagePropertyTIFFDictionary] mutableCopy]
      ?: [NSMutableDictionary dictionary];
  NSMutableDictionary *exif = [properties[(id)kCGImagePropertyExifDictionary] mutableCopy]
      ?: [NSMutableDictionary dictionary];
  properties[(id)kCGImagePropertyTIFFDictionary] = tiff;
  properties[(id)kCGImagePropertyExifDictionary] = exif;

  NSDictionary *updates = [options[@"tags"] isKindOfClass:NSDictionary.class]
      ? options[@"tags"] : @{};
  NSDictionary *definitions = [self exifDefinitions];
  for (NSString *name in updates) {
    NSDictionary *definition = definitions[name];
    if (definition == nil) {
      CFRelease(source);
      return [self errorResult:[NSString stringWithFormat:
          @"Unsupported ImageTooling EXIF tag: %@", name]];
    }
    id rawValue = updates[name];
    id value = rawValue == NSNull.null ? nil : [self typedExifValue:rawValue tag:name];
    id containerKey = definition[@"container"];
    NSMutableDictionary *container = containerKey == NSNull.null
        ? properties : ([containerKey isEqual:(id)kCGImagePropertyTIFFDictionary] ? tiff : exif);
    if (value == nil) [container removeObjectForKey:definition[@"key"]];
    else container[definition[@"key"]] = value;
  }

  if (options[@"gps"] != nil) {
    if (options[@"gps"] == NSNull.null) {
      [properties removeObjectForKey:(id)kCGImagePropertyGPSDictionary];
    } else if ([options[@"gps"] isKindOfClass:NSDictionary.class]) {
      NSDictionary *gpsUpdate = options[@"gps"];
      NSMutableDictionary *gps = [properties[(id)kCGImagePropertyGPSDictionary] mutableCopy]
          ?: [NSMutableDictionary dictionary];
      double latitude = [gpsUpdate[@"latitude"] doubleValue];
      double longitude = [gpsUpdate[@"longitude"] doubleValue];
      gps[(id)kCGImagePropertyGPSLatitude] = @(fabs(latitude));
      gps[(id)kCGImagePropertyGPSLatitudeRef] = latitude < 0 ? @"S" : @"N";
      gps[(id)kCGImagePropertyGPSLongitude] = @(fabs(longitude));
      gps[(id)kCGImagePropertyGPSLongitudeRef] = longitude < 0 ? @"W" : @"E";
      if (gpsUpdate[@"altitude"] == NSNull.null) {
        [gps removeObjectForKey:(id)kCGImagePropertyGPSAltitude];
        [gps removeObjectForKey:(id)kCGImagePropertyGPSAltitudeRef];
      } else if (gpsUpdate[@"altitude"] != nil) {
        double altitude = [gpsUpdate[@"altitude"] doubleValue];
        gps[(id)kCGImagePropertyGPSAltitude] = @(fabs(altitude));
        gps[(id)kCGImagePropertyGPSAltitudeRef] = @(altitude < 0 ? 1 : 0);
      }
      properties[(id)kCGImagePropertyGPSDictionary] = gps;
    }
  }

  NSString *extension = [self extensionForImageType:sourceType];
  NSString *error = nil;
  NSURL *destination = [self cacheURLWithSuffix:@"exif" extension:extension error:&error];
  if (destination == nil) {
    CFRelease(source);
    return [self errorResult:error];
  }
  CGImageDestinationRef imageDestination = CGImageDestinationCreateWithURL(
      (__bridge CFURLRef)destination, sourceType, 1, nil);
  if (imageDestination == nil) {
    CFRelease(source);
    return [self errorResult:@"ImageTooling cannot create the EXIF output"];
  }
  CGImageDestinationAddImageFromSource(
      imageDestination, source, 0, (__bridge CFDictionaryRef)properties);
  BOOL finalized = CGImageDestinationFinalize(imageDestination);
  CFRelease(imageDestination);
  CFRelease(source);
  if (!finalized) {
    return [self errorResult:@"ImageTooling failed to write EXIF metadata"];
  }
  NSDictionary *resultInfo = [self sourceInfoAtURL:destination error:&error];
  if (resultInfo == nil) return [self errorResult:error];
  NSDictionary *attributes = [NSFileManager.defaultManager
      attributesOfItemAtPath:destination.path error:nil];
  return [self valueResult:@{
    @"uri" : destination.absoluteString,
    @"width" : resultInfo[@"width"],
    @"height" : resultInfo[@"height"],
    @"sizeBytes" : attributes[NSFileSize] ?: @0,
  }];
}

- (NSDictionary *)exifDefinitions {
  return @{
    @"Orientation" : @{ @"container" : NSNull.null, @"key" : (id)kCGImagePropertyOrientation },
    @"ImageDescription" : @{ @"container" : (id)kCGImagePropertyTIFFDictionary, @"key" : (id)kCGImagePropertyTIFFImageDescription },
    @"Make" : @{ @"container" : (id)kCGImagePropertyTIFFDictionary, @"key" : (id)kCGImagePropertyTIFFMake },
    @"Model" : @{ @"container" : (id)kCGImagePropertyTIFFDictionary, @"key" : (id)kCGImagePropertyTIFFModel },
    @"Software" : @{ @"container" : (id)kCGImagePropertyTIFFDictionary, @"key" : (id)kCGImagePropertyTIFFSoftware },
    @"Artist" : @{ @"container" : (id)kCGImagePropertyTIFFDictionary, @"key" : (id)kCGImagePropertyTIFFArtist },
    @"Copyright" : @{ @"container" : (id)kCGImagePropertyTIFFDictionary, @"key" : (id)kCGImagePropertyTIFFCopyright },
    @"DateTime" : @{ @"container" : (id)kCGImagePropertyTIFFDictionary, @"key" : (id)kCGImagePropertyTIFFDateTime },
    @"DateTimeOriginal" : @{ @"container" : (id)kCGImagePropertyExifDictionary, @"key" : (id)kCGImagePropertyExifDateTimeOriginal },
    @"OffsetTimeOriginal" : @{ @"container" : (id)kCGImagePropertyExifDictionary, @"key" : (id)kCGImagePropertyExifOffsetTimeOriginal },
    @"UserComment" : @{ @"container" : (id)kCGImagePropertyExifDictionary, @"key" : (id)kCGImagePropertyExifUserComment },
    @"ExposureTime" : @{ @"container" : (id)kCGImagePropertyExifDictionary, @"key" : (id)kCGImagePropertyExifExposureTime },
    @"FNumber" : @{ @"container" : (id)kCGImagePropertyExifDictionary, @"key" : (id)kCGImagePropertyExifFNumber },
    @"ISOSpeedRatings" : @{ @"container" : (id)kCGImagePropertyExifDictionary, @"key" : (id)kCGImagePropertyExifISOSpeedRatings },
    @"FocalLength" : @{ @"container" : (id)kCGImagePropertyExifDictionary, @"key" : (id)kCGImagePropertyExifFocalLength },
    @"LensMake" : @{ @"container" : (id)kCGImagePropertyExifDictionary, @"key" : (id)kCGImagePropertyExifLensMake },
    @"LensModel" : @{ @"container" : (id)kCGImagePropertyExifDictionary, @"key" : (id)kCGImagePropertyExifLensModel },
  };
}

- (id)typedExifValue:(id)value tag:(NSString *)tag {
  NSString *string = [value isKindOfClass:NSString.class] ? value : [value description];
  if ([tag isEqual:@"Orientation"]) return @([string integerValue]);
  if ([tag isEqual:@"ExposureTime"] || [tag isEqual:@"FNumber"]
      || [tag isEqual:@"FocalLength"]) return @([string doubleValue]);
  if ([tag isEqual:@"ISOSpeedRatings"]) return @[ @([string integerValue]) ];
  return string;
}

- (NSString *)exifString:(id)value {
  if (value == nil || value == NSNull.null) return nil;
  if ([value isKindOfClass:NSArray.class]) {
    NSMutableArray *parts = [NSMutableArray array];
    for (id part in value) [parts addObject:[part description]];
    return [parts componentsJoinedByString:@","];
  }
  return [value description];
}

#pragma mark - Source and validation helpers

- (NSDictionary *)sourceInfoAtURL:(NSURL *)url error:(NSString **)error {
  CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, nil);
  if (source == nil) {
    if (error != nil) *error = @"ImageTooling cannot open the image URI";
    return nil;
  }
  NSDictionary *properties = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(
      source, 0, (__bridge CFDictionaryRef) @{(id)kCGImageSourceShouldCache : @NO}));
  CFStringRef type = CGImageSourceGetType(source);
  NSString *typeValue = type != nil ? [(__bridge NSString *)type copy] : nil;
  CFRelease(source);
  NSNumber *rawWidth = properties[(id)kCGImagePropertyPixelWidth];
  NSNumber *rawHeight = properties[(id)kCGImagePropertyPixelHeight];
  if (rawWidth.integerValue < 1 || rawHeight.integerValue < 1) {
    if (error != nil) *error = @"ImageTooling cannot decode the image dimensions";
    return nil;
  }
  NSInteger width = rawWidth.integerValue;
  NSInteger height = rawHeight.integerValue;
  NSInteger orientation = [properties[(id)kCGImagePropertyOrientation] integerValue];
  if (orientation >= 5 && orientation <= 8) {
    NSInteger swapped = width;
    width = height;
    height = swapped;
  }
  NSDictionary *attributes = [NSFileManager.defaultManager
      attributesOfItemAtPath:url.path error:nil];
  return @{
    @"width" : @(width),
    @"height" : @(height),
    @"rawWidth" : rawWidth,
    @"rawHeight" : rawHeight,
    @"orientation" : @(orientation > 0 ? orientation : 1),
    @"mimeType" : [self mimeTypeForImageType:typeValue] ?: NSNull.null,
    @"sizeBytes" : attributes[NSFileSize] ?: NSNull.null,
    @"type" : typeValue ?: @"public.jpeg",
  };
}

- (BOOL)validateSourceInfo:(NSDictionary *)info error:(NSString **)error {
  double pixels = [info[@"rawWidth"] doubleValue] * [info[@"rawHeight"] doubleValue];
  if (pixels > ImageToolingMaxPixels) {
    if (error != nil) *error = @"ImageTooling image is larger than 50 MP";
    return NO;
  }
  return YES;
}

- (BOOL)validateOutputSize:(CGSize)size error:(NSString **)error {
  if (size.width < 1 || size.height < 1
      || size.width > ImageToolingMaxDimension || size.height > ImageToolingMaxDimension) {
    if (error != nil) *error = [NSString stringWithFormat:
        @"ImageTooling output dimensions must not exceed %ld", (long)ImageToolingMaxDimension];
    return NO;
  }
  if (size.width * size.height > ImageToolingMaxPixels) {
    if (error != nil) *error = @"ImageTooling output is larger than 50 MP";
    return NO;
  }
  return YES;
}

- (CGSize)displaySize:(NSDictionary *)info {
  return CGSizeMake([info[@"width"] integerValue], [info[@"height"] integerValue]);
}

- (CGFloat)fitScaleForSize:(CGSize)size
                  maxWidth:(NSNumber *)maxWidth
                 maxHeight:(NSNumber *)maxHeight {
  CGFloat scale = 1.0;
  if (maxWidth != nil && size.width > maxWidth.doubleValue) {
    scale = MIN(scale, maxWidth.doubleValue / size.width);
  }
  if (maxHeight != nil && size.height > maxHeight.doubleValue) {
    scale = MIN(scale, maxHeight.doubleValue / size.height);
  }
  return scale;
}

- (CGSize)scaledSize:(CGSize)size scale:(CGFloat)scale {
  return CGSizeMake(MAX(1, lround(size.width * scale)),
                    MAX(1, lround(size.height * scale)));
}

- (BOOL)parseFormat:(id)value
         defaultJPEG:(BOOL)defaultJPEG
                jpeg:(BOOL *)jpeg
               error:(NSString **)error {
  if (value == nil || value == NSNull.null) {
    *jpeg = defaultJPEG;
    return YES;
  }
  if ([value isEqual:@"jpeg"]) {
    *jpeg = YES;
    return YES;
  }
  if ([value isEqual:@"png"]) {
    *jpeg = NO;
    return YES;
  }
  if (error != nil) *error = [NSString stringWithFormat:@"Invalid ImageTooling format: %@", value];
  return NO;
}

- (NSInteger)quality:(id)value fallback:(NSInteger)fallback {
  return [value respondsToSelector:@selector(integerValue)] ? [value integerValue] : fallback;
}

- (NSInteger)positiveInteger:(id)value fallback:(NSInteger)fallback {
  NSInteger number = [value respondsToSelector:@selector(integerValue)]
      ? [value integerValue] : fallback;
  return number >= 1 ? number : fallback;
}

- (NSInteger)nonNegativeInteger:(id)value fallback:(NSInteger)fallback {
  NSInteger number = [value respondsToSelector:@selector(integerValue)]
      ? [value integerValue] : fallback;
  return number >= 0 ? number : fallback;
}

- (NSNumber *)positiveNumber:(id)value {
  if (![value isKindOfClass:NSNumber.class] || [value doubleValue] < 1) return nil;
  return value;
}

- (NSURL *)imageURL:(id)value {
  if (![value isKindOfClass:NSString.class] || [value length] == 0) return nil;
  NSURL *url = [NSURL URLWithString:(NSString *)value];
  return url != nil && [url.scheme isEqual:@"file"] ? url : nil;
}

- (NSURL *)cacheURLWithSuffix:(NSString *)suffix
                    extension:(NSString *)extension
                        error:(NSString **)error {
  NSURL *caches = [NSFileManager.defaultManager URLsForDirectory:NSCachesDirectory
                                                       inDomains:NSUserDomainMask].firstObject;
  NSURL *directory = [caches URLByAppendingPathComponent:@"LynxImages" isDirectory:YES];
  NSError *directoryError = nil;
  if (![NSFileManager.defaultManager createDirectoryAtURL:directory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:&directoryError]) {
    if (error != nil) *error = @"ImageTooling cannot create the cache directory";
    return nil;
  }
  NSString *fileName = [NSString stringWithFormat:@"%@-%@.%@",
      NSUUID.UUID.UUIDString.lowercaseString, suffix, extension];
  return [directory URLByAppendingPathComponent:fileName];
}

- (NSString *)mimeTypeForImageType:(NSString *)type {
  if (type == nil) return nil;
  return @{
    @"public.jpeg" : @"image/jpeg",
    @"public.png" : @"image/png",
    @"public.heic" : @"image/heic",
    @"public.heif" : @"image/heif",
    @"public.gif" : @"image/gif",
    @"public.webp" : @"image/webp",
    @"org.webmproject.webp" : @"image/webp",
    @"public.tiff" : @"image/tiff",
    @"com.microsoft.bmp" : @"image/bmp",
  }[type];
}

- (NSString *)extensionForImageType:(CFStringRef)type {
  NSString *value = (__bridge NSString *)type;
  if ([value isEqual:@"public.png"]) return @"png";
  if ([value isEqual:@"public.webp"] || [value isEqual:@"org.webmproject.webp"]) return @"webp";
  if ([value isEqual:@"public.heic"]) return @"heic";
  if ([value isEqual:@"public.heif"]) return @"heif";
  if ([value isEqual:@"public.tiff"]) return @"tiff";
  return @"jpg";
}

#pragma mark - JSON helpers

- (NSString *)valueResult:(id)value {
  return [self encodeJSONObject:@{ @"value" : value ?: NSNull.null }];
}

- (NSString *)errorResult:(NSString *)message {
  return [self encodeJSONObject:@{ @"error" : message ?: @"ImageTooling failed" }];
}

- (NSString *)encodeJSONObject:(NSDictionary *)object {
  NSError *error = nil;
  NSData *data = [NSJSONSerialization dataWithJSONObject:object options:0 error:&error];
  if (data == nil) return @"{\"error\":\"ImageTooling serialization failed\"}";
  return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

@end
