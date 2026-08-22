# WebView 模块桥：Autolink 原生组件 + 显式宿主适配器

## 设计边界

`<module-webview>` 内的 H5 通过 `window.__lynxNativeBridge` 调用宿主已注册的 Lynx
Native Modules。Android、iOS、HarmonyOS 使用相同的请求/响应协议；页面代码无需感知平台。

实现遵守两个约束：

1. 原生组件不维护第二份模块注册表。每个宿主适配器复用该 LynxView 已安装的模块注册表；
2. 原生组件与宿主策略分离。Android/iOS 组件由 `autolink/webview-bridge` 注册，宿主只
   负责把当前 view 的模块注册表交给组件；HarmonyOS 的全局 Autolink 注册表对页面不可
   枚举，因此不做全局 Provider，由 behavior 适配器把全局注册表与页面模块表合层后持
   有。

## 页面协议

宿主在每个新文档注入 bootstrap：

```js
const result = await window.__lynxNativeBridge.invoke(
  'Storage',
  'getString',
  ['my.key', null],
);
// 原生 callback 参数统一编码为数组，例如 [null] 或 ['value']。
```

每个文档生成独立 `session`。请求携带 session，响应原样回传；当前文档只处理自己的
session。即使旧文档的异步原生调用在导航完成后才返回，也无法用重复的 request id
错误地结算新文档的 Promise。

`@lynx-template/autolink-webview-bridge/client` 提供 `kv`、`clipboard`、`haptics`、
`statusBar`、`getDeviceInfo`、`getSafeAreaInsets` 等类型化封装；后三者都调用底层
`Device` 模块，并使用同包生成的 RPC 契约。普通浏览器或未接入的宿主中，
`isNativeBridgeAvailable()` 返回 false，调用抛出 `NativeBridgeUnavailableError`。

## 能力授权

桥不提供 URL 或“主页面” allowlist。Native Module 暴露面只由必填的显式模块列表控制：

```tsx
<module-webview
  src="https://app.example.com/page"
  webview-type="module-bridge"
  params={{
    'module-bridge': {
      modules: ['Storage', 'Clipboard'],
    },
  }}
/>
```

- 未配置 `modules`、空数组、或后续更新移除配置时，全部调用均拒绝；
- 列表只授予模块级能力；未知模块和未列出的模块均拒绝；
- 方法名和参数个数来自各 Autolink 包的 `types/platform-native-module.d.ts`，并通过
  `contracts/native-modules.json` 的映射聚合生成；模块对象上的其他公开方法不会被
  WebView 调用；
- URL、重定向和页面内容可信度由宿主业务负责。当前实现没有区分主 frame 与子 frame，
  因而不要给会加载不可信 iframe 的页面授予敏感模块。

## 三端接入

### Android

- `autolink/webview-bridge/android` 声明 `@LynxElement(name = "module-webview")`，基于官方
  `LynxUIWebView` 和 `ILynxWebViewService` 实现 WebView、RPC、参数转换和模块调用；
- `WebviewModuleBridgeHostAdapter` 使用 `RecordingLynxViewBuilder` 记录 Autolink 与宿主
  手动注册的全部模块，并在 build 后把同一注册表挂到 `LynxContext`；
- `LynxLibraryProviderImpl` 由 Lynx processor 生成，并由官方 `library-build` Gradle 插件
  生成的 app-wide Autolink registry 加载；
- `addJavascriptInterface` 方法和 Lynx props setter 均有对应的 R8 keep 规则。

### iOS

- `autolink/webview-bridge/ios` 的 `@LynxElement("module-webview")` 由 CocoaPods Autolink
  生成 registry；
- 自定义 loader 只安装在 `webview-type="module-bridge"`，不会替换普通 `<webview>`；
- `WebviewModuleBridgeHostAdapter` 创建记录型 `LynxModuleBridgeConfig` 并关联 LynxView；
- 模块实例化与 Lynx `CommonModuleCreator` 一致，支持 `LynxContextModule` 的
  `initWithLynxContext:` / `initWithLynxContext:WithParam:`；
- 调用严格校验真实尾部 block callback，并通过 `NSInvocation` 分发到 tasm 线程。

### HarmonyOS

- `WebviewModuleBridgeHostAdapter` 持有「全局 Autolink 模块表 + 页面模块表」的合层结
  果，与 LynxView 的解析顺序一致（页面表覆盖全局表，例如携带宿主状态的 Device）；
- 全局表来自生成的 `@lynx/lynx_autolink_registry` 包导出的 `collectGlobalModules()`——
  它与 `setupGlobal()` 使用同一份 provider 列表（由 vendored `lynx-library-plugin` 生
  成），不维护第二份模块清单；
- `createModuleWebviewBehavior` 把 `ModuleWebviewUI` 以 `module-webview` 注册到该页面；
- ArkWeb 通过 `registerJavaScriptProxy` 接收请求，bootstrap 由
  `javaScriptOnDocumentStart` 注入；
- 模块实例由 `LynxModuleManager` 创建和缓存，调用只接受“全部值参数 + 一个尾部
  callback”的精确参数个数。

## 演示与验收标记

`bundle/main` 首页内嵌 HTML，显式暴露 `KV`、`Clipboard`、`Haptics`、`Device`。
文档收到 bridge-ready 事件后自动执行 KV 写入/读取和 Device 解码；成功时页面显示：

```text
WEBVIEW_BRIDGE_OK · <manufacturer> <model>
```

这个标记同时用于 Android 设备、HarmonyOS 物理设备与 iOS Simulator 的运行验收。
