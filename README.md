# Lynx 三端工程模板

一个以 Lynx 4.0 为基线的多端仓库（HarmonyOS 为使用官方 Autolink 暂时跟随 4.2 nightly）：同一组 ReactLynx bundle 可以被 iOS、Android 和 HarmonyOS 原生宿主打包，也可以从本地 Rspeedy 服务开发，或通过远端发布清单热更新。

## 目录

```text
.
├── .agent/skills       # 项目级 Agent skills 的统一入口
├── package.json        # 仓库级 pnpm 命令与工具依赖
├── autolink.config.json # Autolink TUI 目录与宿主必选策略
├── pnpm-workspace.yaml # autolink/*、bundle/*、lib/* 工作区与统一依赖 catalog
├── biome.json          # 统一 lint、formatter 和 import 整理
├── tsconfig.base.json  # 严格 TypeScript 基线
├── tsconfig.lynx.json  # Lynx JSX 与 Bundler 模块解析
├── app
│   ├── androidApp   # Kotlin / Gradle 原生工程
│   ├── iosApp       # Swift / UIKit / CocoaPods 原生工程（含 Gemfile / Bundler）
│   └── harmonyApp   # ArkTS / Stage 模型原生工程
├── autolink          # Lynx 原生库，三端均由官方 Autolink 注册
│   ├── back          # Back（系统返回拦截 + 预测手势进度）
│   ├── biometric     # Biometric（系统生物识别弹窗 + 锁屏凭证降级）
│   ├── battery       # Battery（电量 + 充电状态）
│   ├── clipboard     # Clipboard
│   ├── device-info   # DeviceInfo（设备信息、安全区、状态栏）
│   ├── display       # Display（宽度 + 亮度 + 常亮）
│   ├── file-system   # FileSystem（系统文件选择器 + URI 文件操作）
│   ├── haptics       # Haptics
│   ├── liquid-glass  # iOS Liquid Glass Element（switch + dropdown）
│   ├── album-utils   # AlbumUtils（相册选图 + 存图）
│   ├── mmkv          # KV（MMKV 字符串存储）
│   ├── router        # Router（原生页面导航 + URL 打开）
│   ├── scanner       # Scanner（系统扫码页 + 图片识码）
│   ├── screenshot    # Screenshot（视图 / 页面截图存入缓存）
│   ├── secure-storage # SecureStorage（系统密钥保护的小型机密存储）
│   ├── sensors       # Sensors（加速度计 + 罗盘流式读数）
│   ├── toast         # Toast（原生轻提示）
│   ├── websocket     # WebSocket
│   └── webview-bridge # module-webview Element 与受控 NativeModule RPC
├── bundle           # 可独立构建和发布的 Lynx bundles
│   └── main         # 默认 Lynx bundle
├── contracts        # NativeModule 名称、声明文件与三端实现的映射元数据
├── lib              # bundles 共享的基础库 workspace packages
│   ├── activity-sheet # 跨 bundle 复用的原生透明底部面板
│   └── bundle-config # 跨 bundle 复用的 Rspeedy 构建配置
└── scripts          # 原生配置、bundle 创建与发布同步脚本
```

项目级 skills 统一维护在根目录 `.agent/skills`：

- `lynx-devtool`：调试已经运行的 Lynx 页面、会话和组件。
- `lynx-native-debug`：构建、安装并验证 Android、iOS 与 HarmonyOS Debug 宿主、HMR 和可用的 CDP 链路。

不要在 `bundle/*` 或其他子项目中复制 skills；通用命令细节放在对应
`references/` 中按需加载。

三个宿主使用相同的资源优先级：

1. Debug 设备配置中按 bundle ID 指定的 Rspeedy URL；
2. 通过 HTTPS 下载且 SHA-256 校验成功的热更新缓存；
3. 安装包内的 `main.lynx.bundle`。

缓存损坏、版本不匹配或网络失败不会覆盖内置兜底资源。详细设计见 [Debug 开发配置](docs/development-settings.md)、[Native Environment 数据契约](docs/native-environment.md)、[NativeModules、原生路由与返回](docs/native-modules.md)、[Lynx 网络请求](docs/networking.md) 和 [热更新协议](docs/hot-update.md)。

原生模块与 Element 库集中维护在 `autolink/`。Android、iOS 与 HarmonyOS 三个宿主都由
Lynx 官方 Autolink 工具扫描各自平台的库、接入依赖并生成 Registry；宿主不维护
Autolink Provider 清单。NativeModule 库均提供 HarmonyOS 源码 HAR；其中 Router
通过 `LynxContext.contextData` 调用宿主的 ArkUI 导航策略，但模块类和注册仍由 Autolink
管理。Back 已纵向封装在 `autolink/back`；Android/iOS 不再手工注册，HarmonyOS 宿主只把
声明式返回事件和路由会话接到包内控制器。StatusBar 与 SafeArea 位于
`autolink/device-info`。iOS 的
`glass-switch` 与 `glass-dropdown` 也已作为
`autolink/liquid-glass` 中的 Element 自动接入。集成细节见
[NativeModules 文档的 Autolink 章节](docs/native-modules.md#lynx-autolink-集成)。

## 环境要求

- Node.js `20.19+` 或 `22.12+`
- pnpm `10.28+`
- Android Studio / JDK 17+ / Android SDK 36 / Android SDK Build Tools 36.0.0
- Xcode / CocoaPods 1.11.3+ / Ruby Bundler（iOS 依赖含 `cocoapods-lynx-library` gem，构建脚本统一走 `bundle exec pod install`）
- DevEco Studio 6.1.1 与 HarmonyOS SDK 24

## Bundle 开发

```bash
pnpm install
pnpm dev:main
```

Rspeedy 默认监听 `0.0.0.0`，终端会给出 bundle URL 和二维码。修改 `bundle/main/src` 后，开发 bundle 内置的 HMR 客户端会接收更新。

常用命令：

```bash
pnpm check                 # TypeScript + Biome
pnpm dev:android -s <serial> # 构建 Android Debug 包并安装、启动到指定 adb 设备
pnpm build                 # 构建所有 workspace bundle
pnpm native:apply          # 将 package.json 的应用标识与 Lynx 版本写入三端原生配置
pnpm native:check          # 检查三端原生配置是否与 package.json 一致
pnpm native:autolink:apply # 按 nativeApp.autolinkModules 更新根依赖（随后运行 pnpm install）
pnpm native:autolink:check # 检查原生 Autolink 启用项与根依赖一致
pnpm native:sync           # 生成发布清单并把 bundle 产物同步进各宿主内置资源
pnpm native:modules:sync   # 重新同步 autolink 模块的共享样板与 Lynx 版本钉
pnpm build:lynx           # 构建、生成发布清单、同步三端内置资源
pnpm build:androidDebug   # 构建 Lynx 产物 + Android Debug APK
pnpm build:androidRelease # 构建 Lynx 产物 + Android Release APK（未签名）
pnpm build:iosDebug       # 构建 Lynx 产物 + iOS Debug（模拟器）
pnpm build:iosRelease     # 构建 Lynx 产物 + iOS Release（未签名）
pnpm build:harmonyDebug   # 构建 Lynx 产物 + HarmonyOS Debug HAP
pnpm build:harmonyRelease # 构建 Lynx 产物 + HarmonyOS Release HAP（未签名）
pnpm new:bundle profile    # 新建 bundle/profile
pnpm new:native-module payment # 新建 autolink/payment 原生模块（三端 stub + 契约）
pnpm test                  # 跑 create-lynx-app 的脚手架测试
pnpm template:export       # 把当前仓库快照导出到 create-lynx-app/template/
```

## 模板发布

`create-lynx-app`（npm 包 `@lynfe/lynx-app`）通过 `pnpm template:export` 生成的快照脚手架新项目；推送 `v*` 标签会触发 GitHub Actions 重新导出模板并发布 npm 包。流程与本地验证方法见 [create-lynx-app/README.md](create-lynx-app/README.md)。

## 原生应用标识

根目录 `package.json` 的 `nativeApp` 是三端安装标识的唯一配置入口：
下面示例展示只额外启用 MMKV 的三端项目（Router 与 WebView bridge 为宿主必需项）：

```json
{
  "nativeApp": {
    "platforms": ["android", "ios", "harmony"],
    "autolinkModules": ["mmkv", "router", "webview-bridge"],
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

`platforms` 是当前项目实际保留的宿主，也是所有原生脚本的共同输入。脚手架的
`--platforms` 会写入该字段、删除未选宿主目录与对应构建命令；配置检查、契约检查和
资源同步只访问启用的平台。`autolinkModules` 决定哪些 `autolink/*` 包作为根直接依赖
暴露给三端官方 Autolink 扫描器；未启用模块的源码和 TypeScript 契约仍会保留，方便
稍后重新开启。修改该数组后运行 `pnpm native:autolink:apply` 和 `pnpm install`。

交互式创建项目时会显示默认全选的多选 TUI；也可以用
`--autolink mmkv,toast` 非交互指定。Router 是所有宿主的导航基础设施，Android/iOS 的
WebView bridge 也是宿主编译依赖，因此这些项目必需项会自动加入且在 TUI 中锁定。

修改标识后运行 `pnpm native:apply`，脚本会同步以下原生配置：

- Android `applicationId`，Debug 额外应用 `debugApplicationIdSuffix`；
- iOS Debug/Release 的 `PRODUCT_BUNDLE_IDENTIFIER`；
- HarmonyOS 的 `bundleName`。

`bundleId` 是三端默认值；需要平台使用不同标识时，可分别设置 `android.applicationId`、`ios.bundleId` 或 `harmony.bundleName` 覆盖。`pnpm check` 会先执行 `native:check`，防止提交未同步的配置。

## Lynx 版本

根目录 `package.json` 的 `lynx` 字段是引擎与 SDK 版本的唯一来源：

```json
{
  "lynx": {
    "engineVersion": "3.9",
    "sdkVersion": "4.0.0",
    "harmonySdkVersion": "4.2.0-nightly.202608180606.150.ga573c3b8"
  }
}
```

- `engineVersion`：各 bundle 由 `@lynx-template/bundle-config` 在构建时直接读取；三端原生
  无法读取 package.json，对应常量（Kotlin `ENGINE_VERSION`、Swift `engineVersion`、
  ETS `ENGINE_VERSION`）由 `pnpm native:apply` 直接写入；
- `sdkVersion`：`pnpm native:sync` 写入发布清单，`pnpm native:apply` 写入宿主 Android
  `build.gradle.kts` 与 iOS `Podfile` 的 Lynx 钉版，`pnpm native:modules:sync` 同步进每个
  autolink 模块的 `android/build.gradle.kts`（`org.lynxsdk.lynx:*` 坐标，servalsvg 除外）；
- `harmonySdkVersion`：HarmonyOS 的 ohpm `@lynx/*` 版本，`pnpm native:apply` 写入宿主
  两个 oh-package.json5，`pnpm native:modules:sync` 写入每个 autolink HAR 的
  oh-package.json5（`@lynx/primjs` 走独立发布通道，不受影响）。

`pnpm check` 里的 `native:check` 与 `native:modules:check` 会校验所有这些副本，修改版本时
只需改 `package.json`，再运行对应的 apply/sync 命令。
HarmonyOS 当前单独固定到 nightly 通道，因为公开稳定版
`4.0.1` 尚未包含官方 Autolink 所需的 `LynxLibraryRegistry`；Android 与 iOS 仍使用
`4.0.0`。nightly 与对应的官方 Hvigor 插件源码提交一起固定，避免通道漂移。

模板默认生成 `com.lynxapp`（Android Release）、`com.lynxapp.debug`（Android Debug）和 `com.lynxapp`（iOS）。HarmonyOS 要求 `bundleName` 至少三段，因此工程显式覆盖为 `com.lynxapp.harmony`。Android 两个变体可以同时安装；AGP 会把 `applicationIdSuffix` 作为点分隔的包名片段，Kotlin `namespace` 则保持 `com.lynxapp`，不随安装标识变化。

## 打包内置资源

```bash
pnpm build:lynx
```

命令会把所有声明了 `lynxBundle` 的 workspace 包构建为自包含 bundle，生成 `bundle/artifacts/latest/manifest.json`，并同步到 `nativeApp.platforms` 启用的目录：

- Android：`app/androidApp/app/src/main/assets/lynxbundle/`
- iOS：`app/iosApp/lynxbundle/`
- HarmonyOS：`app/harmonyApp/entry/src/main/resources/rawfile/lynxbundle/`

默认构建会内联脚本和静态资源，因此每个入口只需发布一个 `.lynx.bundle`。如果启用异步 chunk、external bundle 或关闭资源内联，还需要把额外文件加入 manifest，并扩展三端资源解析逻辑。

这些目录中的 `*.lynx.bundle` 和 `lynx-bundles.json` 都是可重建产物，
已由根目录 `.gitignore` 排除。原生构建命令会先自动执行 `pnpm build:lynx`，
因此新克隆仓库无需单独运行。

```bash
# Android（Debug / 未签名 Release APK，产物在 app/androidApp/app/build/outputs/apk/）
pnpm build:androidDebug
pnpm build:androidRelease

# iOS（Debug 面向模拟器；Release 面向真机但 CODE_SIGNING_ALLOWED=NO 不签名，
#   产物在 app/iosApp/build/Build/Products/，可用 Xcode 重签后安装；
#   首次构建需从源码编译 Lynx 引擎，可能耗时半小时以上，增量构建很快）
pnpm build:iosDebug
pnpm build:iosRelease

# HarmonyOS（未签名 HAP，产物在 app/harmonyApp/entry/build/default/outputs/；
#   默认使用 /Applications/DevEco-Studio.app，可用 DEVECO_HOME 指向其它安装位置）
pnpm build:harmonyDebug
pnpm build:harmonyRelease
```

交互式开发仍推荐各自的 IDE：Android Studio、Xcode（先 `bundle exec pod install`）、
DevEco Studio。
