#import "LynxModuleBridgeLoader.h"
#import "LynxModuleBridgeConfig.h"

#import <Lynx/LynxContextModule.h>
#import <Lynx/LynxUI.h>
#import <Lynx/LynxView.h>
#import <WebKit/WebKit.h>
#import <string.h>

static NSString *const kRPCMessageHandlerName = @"lynxNativeBridge";
static NSString *const kJSApiName = @"__lynxNativeBridge";
static NSString *const kBlockedAppInstallerModule = @"AppInstaller";

static BOOL LynxModuleBridgeIsBlockedModule(NSString *name) {
  return [name isEqualToString:kBlockedAppInstallerModule];
}

static const char *LynxModuleBridgeUnqualifiedType(const char *encoding) {
  while (encoding != NULL && strchr("rnNoORV", encoding[0]) != NULL) {
    encoding++;
  }
  return encoding;
}

@interface LynxModuleBridgeContainer : UIView
@end

@implementation LynxModuleBridgeContainer

- (void)layoutSubviews {
  [super layoutSubviews];
  for (UIView *subview in self.subviews) {
    subview.frame = self.bounds;
  }
}

@end

@interface LynxWeakScriptMessageHandler : NSObject <WKScriptMessageHandler>

@property(nonatomic, weak, nullable) id<WKScriptMessageHandler> delegate;

- (instancetype)initWithDelegate:(id<WKScriptMessageHandler>)delegate;

@end


@implementation LynxWeakScriptMessageHandler

- (instancetype)initWithDelegate:(id<WKScriptMessageHandler>)delegate {
  self = [super init];
  if (self) {
    _delegate = delegate;
  }
  return self;
}

- (void)userContentController:(WKUserContentController *)userContentController
      didReceiveScriptMessage:(WKScriptMessage *)message {
  [self.delegate userContentController:userContentController didReceiveScriptMessage:message];
}

@end

@interface LynxModuleBridgeLoader : NSObject <LynxWebViewLoader>
@end

@interface LynxModuleBridgeLoader () <WKScriptMessageHandler, WKNavigationDelegate>
@property(nonatomic, weak, nullable) id<LynxWebViewLoaderDelegate> delegate;
@property(nonatomic, strong) LynxModuleBridgeContainer *container;
@property(nonatomic, strong) WKWebView *webView;
@property(nonatomic, copy) NSSet<NSString *> *allowedModules;
@property(nonatomic, strong) NSMutableDictionary<NSString *, id<LynxModule>> *modules;
@property(nonatomic, weak, nullable) LynxView *lynxView;
@property(nonatomic, nullable, strong) LynxModuleBridgeConfig *config;
@property(nonatomic, copy) NSString *elementMessageHandlerName;
@property(nonatomic, strong) LynxWeakScriptMessageHandler *messageHandlerProxy;
@end

@implementation LynxModuleBridgeLoader

- (instancetype)initWithDelegate:(id<LynxWebViewLoaderDelegate>)delegate {
  self = [super init];
  if (self) {
    _delegate = delegate;
    _modules = [NSMutableDictionary dictionary];
    _allowedModules = [NSSet set];

    WKUserContentController *content = [[WKUserContentController alloc] init];
    _messageHandlerProxy =
        [[LynxWeakScriptMessageHandler alloc] initWithDelegate:self];
    _elementMessageHandlerName = [[delegate nameOfScriptMessageHandler] copy] ?: @"";
    if (_elementMessageHandlerName.length > 0) {
      [content addScriptMessageHandler:_messageHandlerProxy
                                  name:_elementMessageHandlerName];
    }
    [content addScriptMessageHandler:_messageHandlerProxy name:kRPCMessageHandlerName];
    [content addUserScript:[[WKUserScript alloc]
        initWithSource:[self.class bridgeScript]
       injectionTime:WKUserScriptInjectionTimeAtDocumentStart
        forMainFrameOnly:YES]];

    WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
    configuration.userContentController = content;

    _webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:configuration];
    _webView.navigationDelegate = self;
    _webView.autoresizingMask =
        UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    _container = [[LynxModuleBridgeContainer alloc] init];
    [_container addSubview:_webView];
  }
  return self;
}

- (void)dealloc {
  WKUserContentController *content = self.webView.configuration.userContentController;
  [content removeScriptMessageHandlerForName:kRPCMessageHandlerName];
  if (self.elementMessageHandlerName.length > 0) {
    [content removeScriptMessageHandlerForName:self.elementMessageHandlerName];
  }
  self.messageHandlerProxy.delegate = nil;
  self.webView.navigationDelegate = nil;
  for (id<LynxModule> module in self.modules.allValues) {
    if ([module respondsToSelector:@selector(destroy)]) {
      [module destroy];
    }
  }
}

#pragma mark - LynxWebViewLoader

- (UIView *)getContainerView {
  return self.container;
}

- (WKWebView *)getWebView {
  return self.webView;
}

- (void)setParams:(NSDictionary *)params {
  NSMutableSet<NSString *> *names = [NSMutableSet set];
  NSDictionary *bridge = [params[@"module-bridge"] isKindOfClass:[NSDictionary class]]
                             ? params[@"module-bridge"]
                             : nil;
  NSArray *modules = [bridge[@"modules"] isKindOfClass:[NSArray class]]
                         ? bridge[@"modules"]
                         : nil;
  for (id item in modules) {
    if ([item isKindOfClass:[NSString class]] && [(NSString *)item length] > 0 &&
        !LynxModuleBridgeIsBlockedModule((NSString *)item)) {
      [names addObject:(NSString *)item];
    }
  }
  self.allowedModules = [names copy];
}

- (void)load:(NSString *)urlStr {
  NSURL *url = [NSURL URLWithString:urlStr];
  if (url != nil) {
    [self.webView loadRequest:[NSURLRequest requestWithURL:url]];
  }
}

- (void)loadHtmlString:(NSString *)htmlString {
  [self.webView loadHTMLString:htmlString baseURL:nil];
}

- (void)reload {
  [self.webView reload];
}

- (void)evaluateJavaScript:(NSString *)javaScriptString
         completionHandler:(void (^_Nullable)(id _Nullable, NSError *_Nullable))completion {
  [self.webView evaluateJavaScript:javaScriptString completionHandler:completion];
}

#pragma mark - WKNavigationDelegate

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
  [self.delegate webView:webView didFinishNavigation:navigation];
}

- (void)webView:(WKWebView *)webView
    didFailNavigation:(WKNavigation *)navigation
            withError:(NSError *)error {
  [self.delegate webView:webView didFailNavigation:navigation withError:error];
}

- (void)webView:(WKWebView *)webView
    didFailProvisionalNavigation:(WKNavigation *)navigation
                       withError:(NSError *)error {
  [self.delegate webView:webView didFailNavigation:navigation withError:error];
}

#pragma mark - WKScriptMessageHandler

- (void)userContentController:(WKUserContentController *)userContentController
      didReceiveScriptMessage:(WKScriptMessage *)message {
  if ([message.name isEqualToString:kRPCMessageHandlerName]) {
    [self handleInvoke:message.body];
    return;
  }
  [self.delegate userContentController:userContentController didReceiveScriptMessage:message];
}

#pragma mark - Module dispatch

- (void)handleInvoke:(id)body {
  if (![body isKindOfClass:[NSDictionary class]]) {
    return;
  }
  NSDictionary *request = (NSDictionary *)body;
  NSNumber *idNumber = [request[@"id"] isKindOfClass:[NSNumber class]] ? request[@"id"] : nil;
  NSString *session = [request[@"session"] isKindOfClass:[NSString class]]
                          ? request[@"session"]
                          : nil;
  NSString *moduleName = [request[@"module"] isKindOfClass:[NSString class]]
                             ? request[@"module"]
                             : nil;
  NSString *methodName = [request[@"method"] isKindOfClass:[NSString class]]
                             ? request[@"method"]
                             : nil;
  NSArray *args = [request[@"args"] isKindOfClass:[NSArray class]] ? request[@"args"] : @[];
  if (idNumber == nil || session.length == 0 || moduleName.length == 0 ||
      methodName.length == 0) {
    return;
  }
  long long callId = idNumber.longLongValue;

  if (LynxModuleBridgeIsBlockedModule(moduleName)) {
    [self respond:callId
          session:session
               ok:NO
          payload:[NSString stringWithFormat:@"module '%@' is blocked from webviews",
                                             moduleName]];
    return;
  }
  if (![self.allowedModules containsObject:moduleName]) {
    [self respond:callId
          session:session
               ok:NO
          payload:[NSString stringWithFormat:@"module '%@' is not exposed to this webview",
                                             moduleName]];
    return;
  }
  LynxModuleBridgeConfig *config = [self resolveConfig];
  if (config == nil) {
    [self respond:callId session:session ok:NO payload:@"module bridge config is unavailable"];
    return;
  }
  LynxModuleBridgeEntry *entry = nil;
  for (LynxModuleBridgeEntry *candidate in config.moduleEntries) {
    if ([candidate.name isEqualToString:moduleName]) {
      entry = candidate;
      break;
    }
  }
  if (entry == nil) {
    [self respond:callId
          session:session
               ok:NO
          payload:[NSString stringWithFormat:@"unknown module '%@'", moduleName]];
    return;
  }

  void (^dispatch)(void) = ^{
    @try {
      [self invokeEntry:entry
                 method:methodName
                   args:args
                callId:callId
                session:session];
    } @catch (NSException *exception) {
      [self respond:callId
            session:session
                 ok:NO
            payload:exception.reason ?: @"invoke failed"];
    }
  };
  LynxView *lynxView = self.lynxView;
  if (lynxView != nil) {
    [lynxView runOnTasmThread:dispatch];
  } else {
    dispatch();
  }
}

- (nullable LynxModuleBridgeConfig *)resolveConfig {
  if (self.config != nil) {
    return self.config;
  }
  if (![self.delegate isKindOfClass:[LynxUI class]]) {
    return nil;
  }
  LynxUI *element = (LynxUI *)self.delegate;
  LynxView *view = [element.context.lynxContext getLynxView];
  if (view == nil) {
    return nil;
  }
  self.lynxView = view;
  self.config = [[LynxModuleBridgeCenter sharedCenter] configForView:view];
  return self.config;
}

- (void)invokeEntry:(LynxModuleBridgeEntry *)entry
             method:(NSString *)methodName
               args:(NSArray *)args
             callId:(long long)callId
            session:(NSString *)session {
  id<LynxModule> module = [self moduleForEntry:entry];
  if (module == nil) {
    [self respond:callId session:session ok:NO payload:@"unable to instantiate module"];
    return;
  }
  NSString *selectorName = [entry.moduleClass methodLookup][methodName];
  if (selectorName.length == 0) {
    [self respond:callId
          session:session
               ok:NO
          payload:[NSString stringWithFormat:@"module '%@' has no method '%@'",
                                             entry.name, methodName]];
    return;
  }
  SEL selector = NSSelectorFromString(selectorName);
  NSObject *target = (NSObject *)module;
  NSMethodSignature *signature = [target methodSignatureForSelector:selector];
  if (signature == nil) {
    [self respond:callId session:session ok:NO payload:@"unable to build method signature"];
    return;
  }

  NSUInteger parameterCount = signature.numberOfArguments - 2;
  BOOL hasCallback = NO;
  if (parameterCount > 0) {
    const char *lastEncoding = LynxModuleBridgeUnqualifiedType(
        [signature getArgumentTypeAtIndex:parameterCount + 1]);
    hasCallback = lastEncoding != NULL && strcmp(lastEncoding, "@?") == 0;
  }
  NSUInteger valueCount = hasCallback ? parameterCount - 1 : parameterCount;
  if (args.count != valueCount) {
    [self respond:callId
          session:session
               ok:NO
          payload:[NSString stringWithFormat:@"expected %lu arguments, got %lu",
                                             (unsigned long)valueCount,
                                             (unsigned long)args.count]];
    return;
  }

  NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
  invocation.target = target;
  invocation.selector = selector;
  for (NSUInteger index = 0; index < valueCount; index++) {
    NSUInteger argumentIndex = index + 2;
    const char *encoding = LynxModuleBridgeUnqualifiedType(
        [signature getArgumentTypeAtIndex:argumentIndex]);
    if (encoding != NULL && strcmp(encoding, "@?") == 0) {
      [self respond:callId
            session:session
                 ok:NO
            payload:@"only one trailing callback parameter is supported"];
      return;
    }
    if (![self setArgument:args[index]
              ofInvocation:invocation
                   atIndex:argumentIndex
               forEncoding:encoding]) {
      [self respond:callId
            session:session
                 ok:NO
            payload:[NSString stringWithFormat:@"argument %lu has an unsupported type",
                                               (unsigned long)index]];
      return;
    }
  }

  __block BOOL responded = NO;
  LynxCallbackBlock callback = nil;
  if (hasCallback) {
    long long capturedId = callId;
    NSString *capturedSession = [session copy];
    callback = ^(id result) {
      dispatch_async(dispatch_get_main_queue(), ^{
        if (responded) {
          return;
        }
        responded = YES;
        [self respond:capturedId
              session:capturedSession
                   ok:YES
              payload:@[ result ?: [NSNull null] ]];
      });
    };
    [invocation setArgument:&callback atIndex:parameterCount + 1];
  }
  [invocation invoke];
  if (!hasCallback && !responded) {
    responded = YES;
    [self respond:callId session:session ok:YES payload:@[]];
  }
}

- (nullable id<LynxModule>)moduleForEntry:(LynxModuleBridgeEntry *)entry {
  id<LynxModule> cached = self.modules[entry.name];
  if (cached != nil) {
    return cached;
  }
  Class moduleClass = entry.moduleClass;
  id instance = [moduleClass alloc];
  id<LynxModule> module = nil;
  if ([instance conformsToProtocol:@protocol(LynxContextModule)]) {
    LynxContext *context = [self.lynxView getLynxContext];
    if (entry.param != nil &&
        [instance respondsToSelector:@selector(initWithLynxContext:WithParam:)]) {
      module = [(id<LynxContextModule>)instance initWithLynxContext:context
                                                          WithParam:entry.param];
    } else {
      module = [(id<LynxContextModule>)instance initWithLynxContext:context];
    }
  } else if (entry.param != nil && [instance respondsToSelector:@selector(initWithParam:)]) {
    module = [instance initWithParam:entry.param];
  } else {
    module = [instance init];
  }
  if (module != nil) {
    self.modules[entry.name] = module;
  }
  return module;
}

- (BOOL)setArgument:(id)raw
        ofInvocation:(NSInvocation *)invocation
             atIndex:(NSUInteger)index
         forEncoding:(const char *)encoding {
  if (encoding == NULL) {
    return NO;
  }
  switch (encoding[0]) {
    case '@': {
      id value = [raw isKindOfClass:[NSNull class]] ? nil : raw;
      [invocation setArgument:&value atIndex:index];
      return YES;
    }
    case 'B': {
      BOOL value = [raw boolValue];
      [invocation setArgument:&value atIndex:index];
      return YES;
    }
    case 'c':
    case 'C': {
      char value = (char)[raw intValue];
      [invocation setArgument:&value atIndex:index];
      return YES;
    }
    case 's':
    case 'S': {
      short value = (short)[raw intValue];
      [invocation setArgument:&value atIndex:index];
      return YES;
    }
    case 'i':
    case 'I': {
      int value = [raw intValue];
      [invocation setArgument:&value atIndex:index];
      return YES;
    }
    case 'l':
    case 'L': {
      long value = [raw longValue];
      [invocation setArgument:&value atIndex:index];
      return YES;
    }
    case 'q':
    case 'Q': {
      long long value = [raw longLongValue];
      [invocation setArgument:&value atIndex:index];
      return YES;
    }
    case 'f': {
      float value = [raw floatValue];
      [invocation setArgument:&value atIndex:index];
      return YES;
    }
    case 'd': {
      double value = [raw doubleValue];
      [invocation setArgument:&value atIndex:index];
      return YES;
    }
    default:
      return NO;
  }
}

- (void)respond:(long long)callId
        session:(NSString *)session
             ok:(BOOL)ok
        payload:(id)payload {
  id result = ok ? (payload ?: @[]) : (payload ?: @"invoke failed");
  NSString *key = ok ? @"result" : @"error";
  NSDictionary *envelope =
      @{ @"session" : session, @"id" : @(callId), @"ok" : @(ok), key : result };
  NSData *data = [NSJSONSerialization dataWithJSONObject:envelope options:0 error:nil];
  if (data == nil) {
    return;
  }
  NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
  NSString *script =
      [NSString stringWithFormat:@"window.%@&&window.%@._onResponse(%@)",
                                 kJSApiName, kJSApiName, json];
  dispatch_async(dispatch_get_main_queue(), ^{
    [self.webView evaluateJavaScript:script completionHandler:nil];
  });
}

#pragma mark - Bootstrap

+ (NSString *)bridgeScript {
  static NSString *script = @";";
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    script = @"(function () {"
             @"  if (window.__lynxNativeBridge) { return; }"
             @"  var session = 'wv-' + Date.now().toString(36) + '-' + Math.random().toString(36).slice(2);"
             @"  var nextId = 1;"
             @"  var pending = Object.create(null);"
             @"  function settle(envelope) {"
             @"    if (!envelope || envelope.session !== session) { return; }"
             @"    var entry = pending[envelope.id];"
             @"    if (!entry) { return; }"
             @"    delete pending[envelope.id];"
             @"    if (envelope.ok) {"
             @"      entry.resolve(envelope.result || []);"
             @"    } else {"
             @"      entry.reject(new Error(envelope.error || 'invoke failed'));"
             @"    }"
             @"  }"
             @"  window.__lynxNativeBridge = {"
             @"    invoke: function (moduleName, methodName, args) {"
             @"      var id = nextId++;"
             @"      return new Promise(function (resolve, reject) {"
             @"        pending[id] = { resolve: resolve, reject: reject };"
             @"        window.webkit.messageHandlers.lynxNativeBridge.postMessage({"
             @"          session: session, id: id, module: moduleName,"
             @"          method: methodName, args: args || []"
             @"        });"
             @"      });"
             @"    },"
             @"    _onResponse: settle"
             @"  };"
             @"  window.dispatchEvent(new Event('lynx-native-bridge-ready'));"
             @"})();";
  });
  return script;
}

@end

@implementation LynxModuleBridgeLoaderProvider

- (nullable id<LynxWebViewLoader>)createLynxWebViewLoaderWithDelegate:
    (id<LynxWebViewLoaderDelegate>)delegate {
  return [[LynxModuleBridgeLoader alloc] initWithDelegate:delegate];
}

@end
