#import <Foundation/Foundation.h>
#import <XElement/LynxUIWebView.h>

NS_ASSUME_NONNULL_BEGIN

/** Loader selected explicitly by `<module-webview webview-type="module-bridge">`. */
@interface LynxModuleBridgeLoaderProvider : NSObject <LynxWebViewLoaderProvider>
@end

NS_ASSUME_NONNULL_END
