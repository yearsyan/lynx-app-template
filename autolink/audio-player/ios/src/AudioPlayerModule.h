#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>
#import <Lynx/LynxContextModule.h>

NS_ASSUME_NONNULL_BEGIN

/// Autolinked Lynx bridge exported to JavaScript as `AudioPlayer`.
/// Declares LynxContextModule so the runtime instantiates it through
/// initWithLynxContext:, which owns the event-emitting LynxContext.
@interface AudioPlayerModule : NSObject <LynxContextModule>

@end

NS_ASSUME_NONNULL_END
