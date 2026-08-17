#import "LynxModuleBridgeConfig.h"
#import "LynxModuleBridgeLoader.h"

#import <XElement/LynxUIWebView.h>

@implementation LynxModuleBridgeEntry

- (instancetype)initWithName:(NSString *)name
                 moduleClass:(Class<LynxModule>)moduleClass
                       param:(nullable id)param {
  self = [super init];
  if (self) {
    _name = [name copy];
    _moduleClass = moduleClass;
    _param = param;
  }
  return self;
}

@end

@implementation LynxModuleBridgeConfig {
  NSMutableArray<LynxModuleBridgeEntry *> *_entries;
}

- (instancetype)initWithProvider:(nullable id<LynxTemplateProvider>)provider {
  self = [super initWithProvider:provider];
  if (self) {
    _entries = [NSMutableArray array];
  }
  return self;
}

- (NSArray<LynxModuleBridgeEntry *> *)moduleEntries {
  return [_entries copy];
}

- (void)recordModule:(Class<LynxModule>)moduleClass
                name:(nullable NSString *)name
               param:(nullable id)param {
  NSString *moduleName = name.length > 0 ? name : [moduleClass name];
  if (moduleName.length == 0) {
    return;
  }
  // Lynx's ModuleFactoryDarwin stores registrations in a name-keyed map, so
  // a later registration replaces an earlier one. Mirror that behavior in
  // the adapter's recorded view of the same registry.
  NSIndexSet *existing =
      [_entries indexesOfObjectsPassingTest:^BOOL(LynxModuleBridgeEntry *entry,
                                                   NSUInteger index,
                                                   BOOL *stop) {
        return [entry.name isEqualToString:moduleName];
      }];
  [_entries removeObjectsAtIndexes:existing];
  [_entries addObject:[[LynxModuleBridgeEntry alloc] initWithName:moduleName
                                                      moduleClass:moduleClass
                                                            param:param]];
}

- (void)registerModule:(Class<LynxModule>)module {
  [self recordModule:module name:nil param:nil];
  [super registerModule:module];
}

- (void)registerModule:(Class<LynxModule>)module param:(nullable id)param {
  [self recordModule:module name:nil param:param];
  [super registerModule:module param:param];
}

- (void)registerModule:(Class<LynxModule>)module withName:(NSString *)name {
  [self recordModule:module name:name param:nil];
  [super registerModule:module withName:name];
}

- (void)registerModule:(Class<LynxModule>)module
              withName:(NSString *)name
                 param:(nullable id)param {
  [self recordModule:module name:name param:param];
  [super registerModule:module withName:name param:param];
}

@end

@implementation LynxModuleBridgeCenter {
  NSMapTable<LynxView *, LynxModuleBridgeConfig *> *_configs;
}

+ (instancetype)sharedCenter {
  static LynxModuleBridgeCenter *center = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    center = [[LynxModuleBridgeCenter alloc] init];
  });
  return center;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    _configs = [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsWeakMemory
                                     valueOptions:NSPointerFunctionsStrongMemory];
  }
  return self;
}

- (void)installLoaderProvider {
  [LynxWebViewService sharedInstance].providers[@"module-bridge"] =
      [[LynxModuleBridgeLoaderProvider alloc] init];
}

- (void)registerConfig:(LynxModuleBridgeConfig *)config forView:(LynxView *)view {
  if (config != nil && view != nil) {
    [_configs setObject:config forKey:view];
  }
}

- (nullable LynxModuleBridgeConfig *)configForView:(LynxView *)view {
  return [_configs objectForKey:view];
}

@end
