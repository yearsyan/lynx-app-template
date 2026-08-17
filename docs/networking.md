# Lynx 网络请求

这个模板提供两类互补的业务网络能力：标准 `fetch`/流式响应用于请求-响应与 SSE，
App 自有的 `WebSocket` 用于全双工长连接。WebSocket 模块不会复用或
依赖 Lynx DevTool 的调试连接，接口与示例见
[NativeModules、原生路由、返回与 WebSocket](native-modules.md#业务-websocket)。

Bundle 继续使用 Lynx 标准 `fetch`、`Request`、`Response` 和流式响应 API，不感知原生平台。三端宿主不再依赖官方 HTTP Service，而是在应用源码中实现 Lynx 的 HTTP Service 接口：

| 平台 | Lynx 接口 | 原生传输层 | 实现 |
| --- | --- | --- | --- |
| Android | `ILynxHttpService` | OkHttp | `LynxTemplateHttpService.kt` |
| iOS | `LynxServiceHttpProtocol` | `URLSession` | `LynxTemplateHttpService.m` |
| HarmonyOS | `ILynxHttpService` | Network Kit `@ohos.net.http` | `LynxTemplateHttpService.ets` |

业务 WebSocket 的传输层分别为 Android OkHttp、iOS
`URLSessionWebSocketTask` 和 HarmonyOS Network Kit `@ohos.net.webSocket`。

因此 bundle 中不需要安装 Axios 或平台桥接包：

```ts
const response = await fetch('https://api.example.com/profile', {
  headers: { Accept: 'application/json' },
});

if (!response.ok) throw new Error(`HTTP ${response.status}`);
const profile = await response.json();
```

## Android

`AppHttpClient` 是应用网络栈的单一入口。Lynx `fetch`、开发 bundle 下载和 OTA 下载共享同一个 `OkHttpClient`，业务可以在这里统一加入超时、证书绑定、缓存、鉴权和观测 interceptor。不要在每个 bundle 中分别实现这些策略。

## iOS

自有服务使用系统 `URLSession`，支持普通响应、流式响应和 Server-Sent Events。它实现了 Lynx 的 `setHttpInterceptor`，宿主需要时可以接管、观察或短路请求。

## HarmonyOS

自有服务使用 Network Kit，支持普通响应、流式响应和 Server-Sent Events。当前 Network Kit 枚举支持 `OPTIONS`、`GET`、`HEAD`、`POST`、`PUT`、`DELETE`、`TRACE` 和 `CONNECT`；不支持的方法返回 Lynx 约定的宿主错误状态 `499`。

## 安全边界

- Debug 允许 `http://`，用于局域网 Rspeedy 和本地接口联调。
- Release 的业务 `fetch` 只允许 `https://`；Android/iOS 还保留系统网络安全策略作为第二层限制。
- WebSocket 与之对应：Debug 允许 `ws://`/`wss://`，Release 只允许 `wss://`。
- 原生传输错误使用状态码 `499` 返回；真实 HTTP 4xx/5xx 保持服务器状态码。
- 热更新下载仍由各平台的 `LynxBundleRepository` 负责版本、大小和 SHA-256 校验；它和业务 `fetch` 共用原生传输能力，但不是同一个协议层。

三份实现由 Lynx 4.0.0 HTTP Service 适配而来，保留了原始版权头；许可证与修改说明见仓库根目录的 `THIRD_PARTY_NOTICES.md`。
