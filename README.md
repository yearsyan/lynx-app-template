# Lynx 三端工程模板

一个以 Lynx 4.0 为基线的多端仓库：同一组 ReactLynx bundle 可以被 iOS、Android 和 HarmonyOS 原生宿主打包，也可以从本地 Rspeedy 服务开发，或通过远端发布清单热更新。

## 目录

```text
.
├── .agent/skills       # 项目级 Agent skills 的统一入口
├── package.json        # 仓库级 pnpm 命令与工具依赖
├── pnpm-workspace.yaml # bundle/*、lib/* 工作区与统一依赖 catalog
├── biome.json          # 统一 lint、formatter 和 import 整理
├── tsconfig.base.json  # 严格 TypeScript 基线
├── tsconfig.lynx.json  # Lynx JSX 与 Bundler 模块解析
├── app
│   ├── androidApp   # Kotlin / Gradle 原生工程
│   ├── iosApp       # Swift / UIKit / CocoaPods 原生工程
│   └── harmonyApp   # ArkTS / Stage 模型原生工程
├── bundle           # 可独立构建和发布的 Lynx bundles
│   ├── main         # 默认 Lynx bundle
│   └── native-capabilities # 原生能力与路由 bundle
├── lib              # bundles 共享的基础库 workspace packages
│   └── native-bridge # 共享宿主环境、NativeModules 类型与调用封装
└── scripts          # 原生配置、bundle 创建与发布同步脚本
```

项目级 skills 统一维护在根目录 `.agent/skills`：

- `lynx-devtool`：调试已经运行的 Lynx 页面、会话和组件。
- `lynx-android-cdp-debug`：构建、安装并验证本仓库 Android Debug 宿主及 DevTool 连通性。

不要在 `bundle/*` 或其他子项目中复制 skills；通用命令细节放在对应
`references/` 中按需加载。

三个宿主使用相同的资源优先级：

1. Debug 设备配置中按 bundle ID 指定的 Rspeedy URL；
2. 通过 HTTPS 下载且 SHA-256 校验成功的热更新缓存；
3. 安装包内的 `main.lynx.bundle`。

缓存损坏、版本不匹配或网络失败不会覆盖内置兜底资源。详细设计见 [Debug 开发配置](docs/development-settings.md)、[Native Environment 数据契约](docs/native-environment.md)、[NativeModules、原生路由与返回](docs/native-modules.md)、[Lynx 网络请求](docs/networking.md) 和 [热更新协议](docs/hot-update.md)。

## 环境要求

- Node.js `20.19+` 或 `22.12+`（不要使用当前不受支持的 Node 25）
- pnpm `10.28+`
- Android Studio / JDK 17+ / Android SDK 34 / Android SDK Build Tools 36.0.0
- Xcode / CocoaPods 1.11.3+
- DevEco Studio 6.1.1 与 HarmonyOS SDK 24

## Bundle 开发

```bash
pnpm install
pnpm dev:main
pnpm dev:websocket # 可选：启动 ws://0.0.0.0:8787 echo 验证服务
```

Rspeedy 默认监听 `0.0.0.0`，终端会给出 bundle URL 和二维码。修改 `bundle/main/src` 后，开发 bundle 内置的 HMR 客户端会接收更新。

常用命令：

```bash
pnpm check                 # TypeScript + Biome
pnpm build                 # 构建所有 workspace bundle
pnpm native:apply          # 将 package.json 的应用标识同步到三端
pnpm native:check          # 检查三端应用标识是否同步
pnpm release               # 构建、生成发布清单、同步三端内置资源
pnpm new:bundle profile    # 新建 bundle/profile
```

根 pnpm workspace 同时管理 `bundle/*` 和 `lib/*`。每个可发布 bundle 的 `package.json` 都需要 `lynxBundle` 字段，`lynxBundle.name` 是不随目录重构改变的发布标识；`lib/*` 则存放不独立发布为 Lynx bundle 的共享基础库。发布脚本只扫描 `bundle/*`。依赖版本统一维护在根目录 `pnpm-workspace.yaml` 的 catalog 中；格式、lint 和 TypeScript 基线配置也统一放在仓库根目录。

`lib/native-bridge` 中的 `@lynx-template/native-bridge` 提供统一的 `nativeEnvironment` 数据契约，以及三端一致的 MMKV、原生路由、返回接管和业务 WebSocket API。`main` 中的 Native Module Lab 可以写入 MMKV、验证 WebSocket echo、打开 `native-capabilities.lynx.bundle`，以及用透明原生页面展示 Lynx 半弹窗；`native-capabilities` 也覆盖了返回拦截和手势进度。接口和扩展方式见 [Native Environment 数据契约](docs/native-environment.md) 与 [NativeModules、原生路由、返回与 WebSocket](docs/native-modules.md)。

## 原生应用标识

根目录 `package.json` 的 `nativeApp` 是三端安装标识的唯一配置入口：

```json
{
  "nativeApp": {
    "bundleId": "com.lynxapp",
    "android": {
      "debugApplicationIdSuffix": ".debug"
    },
    "harmony": {
      "bundleName": "com.lynxapp.harmony"
    }
  }
}
```

修改后运行 `pnpm native:apply`，脚本会同步以下原生配置：

- Android `applicationId`，Debug 额外应用 `debugApplicationIdSuffix`；
- iOS Debug/Release 的 `PRODUCT_BUNDLE_IDENTIFIER`；
- HarmonyOS 的 `bundleName`。

`bundleId` 是三端默认值；需要平台使用不同标识时，可分别设置 `android.applicationId`、`ios.bundleId` 或 `harmony.bundleName` 覆盖。`pnpm check` 会先执行 `native:check`，防止提交未同步的配置。

模板默认生成 `com.lynxapp`（Android Release）、`com.lynxapp.debug`（Android Debug）和 `com.lynxapp`（iOS）。HarmonyOS 要求 `bundleName` 至少三段，因此工程显式覆盖为 `com.lynxapp.harmony`。Android 两个变体可以同时安装；AGP 会把 `applicationIdSuffix` 作为点分隔的包名片段，Kotlin `namespace` 则保持 `com.lynxapp`，不随安装标识变化。

## 本地原生联调

先运行 `pnpm dev:main`，再打开三端 Debug App 右上角的 `DEV`：

- `API Server` 会传入所有 bundle 的 `nativeEnvironment.apiServer`；
- `Bundle servers` 每行使用 `bundle-id=URL`，例如 `main=http://192.168.1.10:3000`；
- 服务根 URL 自动补成 `/<bundle-id>.lynx.bundle`，也可直接填写完整 `.lynx.bundle` URL；
- 保存或清空后主 bundle 会立即重载。配置只保存在当前设备。

Debug 配置页和读取逻辑不会进入 Release 产物。详细格式、优先级和变体隔离见 [Debug 开发配置](docs/development-settings.md)。以下平台配置仍作为无人值守构建或旧流程的 Debug fallback。

### Android

```bash
cp app/androidApp/local.properties.example app/androidApp/local.properties
```

模拟器使用 `http://10.0.2.2:3000/main.lynx.bundle`；真机改成电脑局域网 IP。`lynx.dev.bundle.url` 只在 Debug 生效，Release 禁止明文 bundle URL。

Android 宿主默认只打包 `arm64-v8a`。Lynx DevTool 只存在于 Debug 依赖和源码集，并使用 PrimJS/QuickJS 桥接；Release 不包含 DevTool、V8 runtime 或 V8 bridge。

Android 构建工具链为 AGP `9.3.1`、Gradle `9.5.0` 和 Kotlin `2.4.10`。AGP 9 使用内置 Kotlin，KGP 版本通过根构建脚本统一锁定，不再应用 `org.jetbrains.kotlin.android` 插件。

#### 用 CDP 调试 Android bundle

Debug App 会启动 Lynx DebugRouter。它不是 WebView 的 Chrome `/json` 端点；使用 `agent-lynx` 发现客户端和 bundle session，再发送 Lynx 支持的 CDP 命令：

```bash
npx --yes agent-lynx list-clients --no-daemon
npx --yes agent-lynx list-sessions --client '<client-id>' --no-daemon

npx --yes agent-lynx cdp \
  --client '<client-id>' \
  --session 1 \
  --method Runtime.evaluate \
  '{"expression":"6 * 7","returnByValue":true}' \
  --no-daemon

npx --yes agent-lynx cdp \
  --client '<client-id>' \
  --session 1 \
  --method DOM.getDocument \
  '{"depth":2}' \
  --no-daemon
```

`Runtime`/`Debugger` 由 QuickJS bridge 提供，不要求引入 V8。调试监听、DevTool 依赖和初始化代码均只存在于 Debug 变体。

### iOS

在 Xcode Scheme 的 Run → Arguments → Environment Variables 添加：

```text
LYNX_DEV_BUNDLE_URL=http://127.0.0.1:3000/main.lynx.bundle
```

模拟器可用 `127.0.0.1`，真机使用电脑局域网 IP。Debug 使用独立的 `Info-Debug.plist` 放行本地 HTTP，Release 保持 ATS 默认安全策略。

### HarmonyOS

编辑 `app/harmonyApp/entry/src/main/ets/config/BundleConfig.ets` 的 `DEV_BUNDLE_URL`。真机同样使用电脑局域网 IP。命令行构建需选择对应 target：Debug 使用 `entry@debug`，Release 使用 `entry@release`。

## 打包内置资源

```bash
pnpm release
```

命令会把所有声明了 `lynxBundle` 的 workspace 包构建为自包含 bundle，生成 `bundle/artifacts/latest/manifest.json`，并同步到：

- Android：`app/androidApp/app/src/main/assets/`
- iOS：`app/iosApp/`
- HarmonyOS：`app/harmonyApp/entry/src/main/resources/rawfile/`

默认构建会内联脚本和静态资源，因此每个入口只需发布一个 `.lynx.bundle`。如果启用异步 chunk、external bundle 或关闭资源内联，还需要把额外文件加入 manifest，并扩展三端资源解析逻辑。

这些目录中的 `*.lynx.bundle` 和 `lynx-bundles.json` 都是可重建产物，
已由根目录 `.gitignore` 排除。新克隆仓库在打包任一原生宿主前必须先运行
`pnpm release`。

随后按普通原生项目打包：

```bash
# Android
cd app/androidApp && ./gradlew assembleDebug

# iOS
cd app/iosApp && pod install
open iosApp.xcworkspace

# HarmonyOS
cd app/harmonyApp && ohpm install
# 再由 DevEco Studio 构建 HAP；也可使用 hvigorw，并选择
# Debug 的 entry@debug 或 Release 的 entry@release target。
```

## 网络请求

Bundle 使用标准 `fetch`，并通过 App 自有的 `NativeWebSocketModule` 建立长连接。三端均由应用源码对接原生传输层：Android 使用共享的 OkHttpClient，iOS 使用 URLSession，HarmonyOS 使用 Network Kit；业务 WebSocket 不依赖 Lynx DevTool。Debug 可访问本地 HTTP/WS，Release 只接受 HTTPS/WSS。接入点、流式响应、WebSocket 和定制方式见 [Lynx 网络请求](docs/networking.md)。

## 热更新

将 `bundle/artifacts/latest/manifest.json` 与同目录的 `*.lynx.bundle` 原样上传到 HTTPS CDN，然后配置清单地址：

- Android：`local.properties` 的 `lynx.update.manifest.url`（CI 可在生成该文件时注入）；
- iOS：Info.plist 的 `LynxUpdateManifestURL` 或进程环境变量 `LYNX_UPDATE_MANIFEST_URL`；
- HarmonyOS：`BundleConfig.UPDATE_MANIFEST_URL`。

客户端会校验 `schemaVersion`、`engineVersion`、文件大小和 SHA-256，写入私有目录后切换到新 bundle。发布环境必须使用 HTTPS。SHA-256 只保证完整性；正式业务还应对 manifest 增加离线签名并在客户端固化公钥，详见 [热更新协议](docs/hot-update.md)。

## 版本升级

Lynx bundle 的 `engineVersion` 不能高于宿主 SDK。升级时同步修改：

- `bundle/*/lynx.config.ts` 的 `pluginReactLynx({ engineVersion })`；
- `scripts/sync-native.mjs` 中的引擎/SDK 版本；
- Android Maven、iOS Pods、HarmonyOS ohpm 的 Lynx 依赖版本。

当前宿主 SDK 为 `4.0.0`，bundle `engineVersion` 为 `3.9`。这是因为当前 Rspeedy 0.16.3 编译器最高支持 3.9；按照 Lynx 的向后兼容规则，3.9 bundle 可以运行在 4.0 宿主引擎上。

## 官方参考

- [Lynx 快速开始](https://lynxjs.org/4.0/guide/start/quick-start.html)
- [接入现有原生应用](https://lynxjs.org/4.0/guide/start/integrate-with-existing-apps.html)
- [兼容性与 engineVersion](https://lynxjs.org/4.0/guide/compatibility.html)
- [Rspeedy 输出文件](https://lynxjs.org/4.0/rspeedy/output.html)
- [Lynx DevTool 集成](https://lynxjs.org/4.0/guide/start/integrate-lynx-devtool.html)
