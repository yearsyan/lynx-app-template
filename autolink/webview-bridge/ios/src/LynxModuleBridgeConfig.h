#import <Foundation/Foundation.h>
#import <Lynx/LynxConfig.h>
#import <Lynx/LynxModule.h>
#import <Lynx/LynxView.h>

NS_ASSUME_NONNULL_BEGIN

/** One native-module registration captured from a LynxConfig. */
@interface LynxModuleBridgeEntry : NSObject

@property(nonatomic, copy, readonly) NSString *name;
@property(nonatomic, assign, readonly) Class<LynxModule> moduleClass;
@property(nonatomic, nullable, readonly) id param;

- (instancetype)initWithName:(NSString *)name
                 moduleClass:(Class<LynxModule>)moduleClass
                       param:(nullable id)param NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

/** Records the exact native-module registry installed on an owning LynxView. */
@interface LynxModuleBridgeConfig : LynxConfig

@property(nonatomic, copy, readonly) NSArray<LynxModuleBridgeEntry *> *moduleEntries;

@end

/** Per-view hand-off used by the app's explicit WebView bridge host adapter. */
@interface LynxModuleBridgeCenter : NSObject

+ (instancetype)sharedCenter;

/** Installs the loader under `webview-type="module-bridge"`. Idempotent. */
- (void)installLoaderProvider;

- (void)registerConfig:(LynxModuleBridgeConfig *)config forView:(LynxView *)view;
- (nullable LynxModuleBridgeConfig *)configForView:(LynxView *)view;

@end

NS_ASSUME_NONNULL_END
