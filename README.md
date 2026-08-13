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

- Node.js `20.19+` 或 `22.12+`
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
