# NativeModules、系统 Picker、原生路由、状态栏、返回与 WebSocket

## 设计目标

原生能力按功能纵向封装：每个 `autolink/*` 包同时拥有三端实现、原始 TypeScript
调用契约、生成的 raw facade，以及手写的 Promise API、参数校验、返回值解码和事件
生命周期；需要 React 的能力通过包内 `/react` 子路径导出 hooks。每个包的
`bridge.generated.ts` 按 facade 的实际使用情况生成该模块专用的 resolver、callback 转
Promise 和结构化值/旧 JSON 兼容解码，不依赖中心 runtime 或 host facade。Back 的原生
实现、事件校验、Promise facade、拦截栈与 React hook 与 Router 一起位于
`autolink/navigation`。
Android、iOS 和 HarmonyOS 宿主分别注册同名原生模块，业务 bundle 不需要根据平台分支调用：

- `Storage`：一个模块承载两个后端——`kv` 以共享 MMKV 保存字符串（JSON 编解码由共享 TypeScript 层完成）；`secureStorage` 面向小型机密数据（token、会话密钥等）的 get / set / remove，Android 用 Keystore AES-GCM 加密、iOS 用 Keychain、HarmonyOS 用 HUKS；
- `Navigation`：打开另一个 bundle 对应的原生页面、关闭当前页面或打开系统 URL，同时让当前 Lynx 页面同步声明是否接管系统返回并接收返回生命周期事件；
- `Clipboard`：读写系统剪贴板纯文本；
- `Haptics`：单击式震动反馈，分 light / medium / heavy 三档；
- `Biometric`：静默查询生物识别（指纹 / 面容）可用性，并拉起系统认证弹窗，可选降级到锁屏凭证；
- `AlbumUtils`：从系统相册选择一张或多张图片，或把图片 URI 保存回系统相册；
- `FileSystem`：通过系统文件选择器选择一个或多个文件，查询 Picker URI 元数据、复制到应用缓存、读取 UTF-8 文本或 Base64，并在缓存沙箱内写入 / 删除 / 列举文件；
- `Device`：按需读取机型、OS/App 版本、密度、locale、平板/折叠屏与当前安全区，负责状态栏前景样式，读取电量（0..1，读不到时为 null）与充电状态，查询屏幕/窗口/LynxView 宽度（统一为 Lynx 逻辑像素）、窗口亮度与屏幕常亮，并提供加速度计与罗盘（磁北方位角）流式读数（经 `GlobalEventEmitter` 事件回传，监听计数归零自动停流）；TypeScript 提供 `deviceInfo`、`safeArea`、`statusBar`、`display`、`battery`、`sensors` facade；
- `Toast`：一次性原生轻提示（info / success / error），替代 bundle 内自绘的 `<ToastHost />` 组件；
- `NetworkInfo`：按需查询当前网络类型（wifi / cellular / ethernet / other / none），变化经 `networkInfo` 事件回传；
- `ImageTooling`：读取图片元数据，完成缩放、单区域裁剪、横拼/竖拼/图层叠加，并读取、修改或清除 EXIF/GPS；位图不经过 JS 通道；
- `WebSocket`：提供不依赖 DevTool 的长连接、文本/二进制收发和生命周期事件；
- `Screenshot`：把整个 LynxView、某个元素或当前原生页面截为 PNG/JPEG 写入应用缓存目录；
- `Share`：调起系统分享面板发送文本、链接与本地文件（截图 / 相册 / 文件产物）；
- `Scanner`：拉起全屏扫码页识别 QR / 条形码，并支持对相册图片本地识码；
- `AudioPlayer`：播放本地音频文件（`file://` / Android `content://`），按 `media` / `ambient` / `alarm` / `notification` 四种流路由音量键与音频焦点，进度与状态经 `audioPlayer` 事件回传；
- `Storage`：小型机密数据（token、会话密钥等）的 get / set / remove，Android 用 Keystore AES-GCM 加密、iOS 用 Keychain、HarmonyOS 用 HUKS；
`Navigation`、`WebSocket`、`Storage`、`Clipboard`、`Haptics`、`AlbumUtils`、`FileSystem`、
`Biometric`、`Device`、`NetworkInfo`、`ImageTooling`、`Screenshot`、`Scanner`、
`AudioPlayer`、`Toast` 与 `Share` 均由 `autolink/` workspace 目录中的三端原生库提供并自动注册
（见下文「Lynx Autolink 集成」）。HarmonyOS 使用 4.2 nightly 的官方 Hvigor Autolink
（源码 HAR + 全局 Registry + AppStartup）。HarmonyOS 的 Back 能力由 Autolink 注册的
Navigation 模块承载，
宿主只将 ArkUI 的离散 `onBackPress` 与 route registration 通过 `LynxContext.contextData`
接到包内控制器。`DeviceRegistration` 同样逐 `LynxView` 接入安全区监听和路由状态栏
状态，但模块类与系统 API 实现都属于 `autolink/device`。Navigation 的 ArkUI 导航策略
留在宿主，通过 contextData 注入，不参与模块注册。

三个平台都使用 MMKV ID `lynx.native.kv`。同一 App 内的所有 bundle 共享这个实例，但不同平台、不同设备之间不会自动同步数据。

### 契约来源与分层

每个 Autolink NativeModule 的原始调用签名定义在所属包的
`types/platform-native-module.d.ts`，例如 `Storage` 位于
`autolink/storage/types/platform-native-module.d.ts`（KV 原语与 `secure` 前缀的机密原语在同一声明中）。声明类本身就是 JS 侧的原始类型，
不再在聚合包里复制一遍方法签名。路由与 Back 的声明位于
`autolink/navigation/types/platform-native-module.d.ts`；设备、StatusBar、SafeArea、
电量、显示与传感器的声明位于
`autolink/device/types/platform-native-module.d.ts`。仓库不再需要 `lib/native-host`。

`contracts/native-modules.json` 只保存模块名、声明位置、Autolink 包和三端实现位置的
映射元数据。`pnpm native:contracts:generate` 读取上述 TypeScript 声明，生成
`autolink/webview-bridge/src/contracts.generated.ts` 的模块名、方法白名单和参数个数，
同时在每个 NativeModule Autolink 包生成 `src/native.generated.ts`（raw 类型/模块名）和
`src/bridge.generated.ts`（包内桥接辅助函数）。包根入口 `src/index.ts` 是手写 facade，
生成器不会覆盖；原始类型与模块名通过 `/raw` 子路径提供，内部桥接辅助函数不属于公开
exports。WebView RPC 契约不再聚合或依赖所有 raw interface；业务 bundle 直接依赖所使用的
Autolink 包，浏览器页面按需使用 `@lynx-template/autolink-webview-bridge/client`。

原生方法仍可使用 callback ABI，Promise 在所属包的 facade 内完成。返回值优先使用
NativeModule 可直接传输的对象/数组；尚未迁移的三端实现可以继续返回 JSON 字符串，
每个包生成的 `decodeNativeValue` / `decodeNativeEnvelope` 同时接受两种形式。无论传输
形式如何，模块自己的 facade 都必须做运行时校验，不能把原生返回值仅靠 TypeScript
断言交给业务层。

`pnpm native:contracts:check` 除了检查生成物，还会核对
`package.json#nativeApp.platforms` 中启用平台的原生实现：Android 的
`@LynxMethod`、iOS 的 `methodLookup`、HarmonyOS 的模块方法都必须与声明中的
名称和参数个数一致。修改已有模块时更新所属包的声明和三端实现；新增模块用
`pnpm new:native-module <name>` 一步生成三端 stub、包骨架、契约元数据和宿主注册
（生成的 `ping` 示例方法可直接通过检查），再替换为真实实现。该检查已接入 `pnpm check`。

## JavaScript API

业务代码直接依赖对应功能包，不访问全局 `NativeModules`：

```tsx
import { albumUtils } from '@lynx-template/autolink-album-utils';
import { backStack } from '@lynx-template/autolink-navigation';
import { battery } from '@lynx-template/autolink-device';
import { statusBar } from '@lynx-template/autolink-device';
import { fileSystem } from '@lynx-template/autolink-file-system';
import { kv } from '@lynx-template/autolink-storage';
import { router } from '@lynx-template/autolink-navigation';

async function saveSession() {
  'background only';
  await kv.setJSON('session', { token: 'example' });
  const session = await kv.getJSON('session', { token: '' });
  return session.token;
}

async function openProfile() {
  'background only';
  await router.open({
    bundle: 'profile',
    statusBarStyle: 'dark-content',
    params: { userID: '42' },
  });
}

async function useDarkPageChrome() {
  'background only';
  await statusBar.setStyle('light-content');
}

async function openPresentPage() {
  'background only';
  await router.open({
    bundle: 'native-capabilities',
    animation: 'present',
    // 默认即为无透明度动画 + 从/向屏幕下方完整推入推出；两个阶段可单独覆盖。
    present: {
      enter: { opacity: false, push: true },
      exit: { opacity: false, push: true },
    },
    params: { mode: 'present', source: 'main' },
  });
}

async function openExternalPage() {
  'background only';
  // The system resolves the scheme: any installed app that registered it can
  // handle the URL.
  await router.openURL('weixin://');
}

async function selectAttachments() {
  'background only';
  const images = await albumUtils.pick({ maxSelection: 3 });
  const files = await fileSystem.pick({ maxSelection: 5 });
  const firstFile = files[0];
  const firstFileInfo = firstFile ? await fileSystem.stat(firstFile) : null;
  return { images, files, firstFileInfo };
}
```

Lynx NativeModules 在后台线程使用，因此直接或间接访问它们的函数要包含 `'background only'`。共享封装把原生 callback 转为 Promise，并在原生返回非空错误字符串时 reject。

### kv 能力（Storage 模块）

| 方法 | 说明 |
| --- | --- |
| `setString(key, value)` | 保存字符串 |
| `getString(key, defaultValue?)` | 读取字符串，缺失时返回默认值或 `null` |
| `remove(key)` | 删除一个键 |
| `contains(key)` | 判断键是否存在 |
| `clear()` | 清空这个 App 的 Lynx MMKV 实例 |
| `setJSON(key, value)` | JSON 序列化后保存 |
| `getJSON(key, defaultValue)` | 读取并解析 JSON；缺失或格式错误时返回默认值 |

当前契约刻意保持为字符串原语，不包含二进制、大对象、跨设备同步或事务。业务需要命名空间时，应在 key 前增加 bundle 或业务前缀。

### secureStorage 能力（Storage 模块）

| 方法 | 说明 |
| --- | --- |
| `setString(key, value)` | 加密保存一个小型机密字符串 |
| `getString(key, defaultValue?)` | 读取并解密；缺失（或校验失败，见下文）时返回默认值或 `null` |
| `remove(key)` | 删除一个键（键不存在同样视为成功） |

`secureStorage`（Storage 模块的 `secure` 前缀方法）面向 token、会话凭证等小型机密数据，value 上限 65536 字符；三端实现：

- **Android**（`autolink/storage`）：AES-256-GCM 密钥保存在 AndroidKeyStore 中且不可导出，落盘的只有随机 IV 与密文（应用私有 `SharedPreferences`）；
- **iOS**（`autolink/storage`）：Keychain 通用密码条目（`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`，不随备份迁移到其他设备）；
- **HarmonyOS**（`autolink/storage` HAR）：AES-256-GCM 密钥保存在 HUKS 中，密文存放在专用 MMKV 实例 `lynx.secure.storage`。

与 `kv` 不同，数据不跨平台、不跨设备同步。密文被篡改或系统密钥被清除时，
GCM 校验失败，`getString` 按缺失处理并返回默认值；`remove` 与 KV 一致（幂等）。
存放结构化机密时仍由调用方自行 JSON 编解码。

### 路由参数

```ts
interface RouteOptions {
  bundle: string;
  statusBarStyle?: 'dark-content' | 'light-content';
  animation?: 'default' | 'fade' | 'none' | 'present';
  // 仅 animation 为 'present' 时生效
  present?: {
    scrimColor?: string; // '#AARRGGBB'，默认 '#59000000'
    backdropTransition?: boolean; // 背景（上一页截图）的缩小/复原编舞，默认 true
    enter?: {
      opacity?: boolean; // 入场透明度动画，默认 false
      push?: boolean; // 从屏幕下方完整推入，默认 true
    };
    exit?: {
      opacity?: boolean; // 出场透明度动画，默认 false
      push?: boolean; // 向屏幕下方完整推出，默认 true
    };
    /** @deprecated 仅作为 enter.push / exit.push 的兼容默认值 */
    contentTransition?: boolean;
    backdropBlur?: boolean; // 背景改用降采样模糊截图，默认 false
  };
  params?: Record<string, unknown>;
}
```

打开与关闭的原生过渡动画由 `animation` 控制：`default` 保持各平台标准
推入过渡，`fade` 双向淡入淡出，`none` 打开与关闭都瞬时完成，
`present` 播放类 iOS present 转场（见下节）。非法取值会被共享
TypeScript 层和三端原生模块分别拒绝。

`bundle` 必须匹配 `^[a-z0-9][a-z0-9-]*$`，并与 workspace `package.json` 的 `lynxBundle.name` 一致。路由页通过 init data 收到统一结构：

```json
{
  "route": {
    "bundle": "native-capabilities",
    "statusBarStyle": "dark-content",
    "animation": "present",
    "params": {
      "source": "main"
    }
  }
}
```

页面调用 `router.close()` 返回上一层。根路由上 Android/Harmony 宿主会把应用
退到后台（Android `moveTaskToBack`、Harmony `moveAbilityToBackground`，保留
任务栈，再次进入即时恢复）；iOS 宿主则返回「根路由不可关闭」错误。

### present 转场（截图背景）

`animation: 'present'` 不依赖任何透明原生页面，而是由宿主在打开前对当前
页面截图，新页面以不透明方式打开：

1. 宿主截取当前页面像素（Android `PixelCopy`、iOS `drawViewHierarchyInRect`、
   HarmonyOS `window.snapshot()`）；
2. 以无系统动画方式打开新的不透明页面，并在其首帧渲染前把截图铺为背景层，
   LynxView 背景透明——首屏内容就绪前用户看到的是与上一页像素一致的截图，
   切页零感知；
3. Lynx 首屏回调（`onFirstScreen`）触发后播放编舞：截图背景缩小、下移并
   加圆角（底边对齐屏幕底部，顶边让出状态栏，模拟“前一页后退”）；内容默认
   不改变透明度，从屏幕下方一个完整视口外推入，因此第一帧可见面积严格为 0；
   截图与内容之间还有一层 35% 黑色遮罩原地淡入（静止、不随内容滑动）；
4. 关闭时按独立的 `exit` 配置退出并复原截图，动画结束后才真正关页（无系统
   转场）。露出的真实上一页与复原后的截图像素对齐，`router.close()` 与系统
   返回键都走这条路径。

终态下截图背景保持缩小停留在页面底层，页面内容自行决定露出多少：弹层式
页面顶部留透明即可看到“缩小的上一页”（由原生遮罩统一压暗，页面无需自绘
遮罩），全屏不透明内容则完全覆盖它。
`bundle/main` 的「present 转场」演示页展示了这种弹层式布局。

present 的原生 chrome 都可配置（`present` 选项，三端行为一致）：

- `scrimColor`：截图与内容之间那层遮罩的颜色，`'#AARRGGBB'` 格式（alpha
  在前，即浓度），默认 `'#59000000'`（35% 黑）；传 `'#00000000'` 等于不压暗；
- `backdropTransition: false`：清除上一页截图的缩小/复原编舞——截图保持
  全屏静止作为背景（等同旧透明页面的观感）；
- `enter` / `exit`：分别配置新页面入场与出场，两个阶段互不影响。每个阶段的
  `opacity` 默认 `false`（无透明度动画），`push` 默认 `true`（从/向屏幕下方
  一个完整视口推入推出）；`push: true` 的入场首帧可见面积为 0。两项都为
  `false` 时该阶段内容瞬时出现/消失；
- `contentTransition`：旧调用兼容项，仅在对应阶段未显式设置 `push` 时作为
  `enter.push` 和 `exit.push` 的默认值；新代码应使用 `enter` / `exit`；
- 背景或当前阶段的内容只要有动画，遮罩就随该阶段原地淡入/淡出；都关闭时
  遮罩从第一帧起静止显示；
- `backdropBlur: true`：截图改以 1/3 分辨率捕获并做高斯模糊（Android 12+
  用 `RenderEffect`，更低版本为 CPU 盒式模糊；iOS 为 `CIGaussianBlur`；
  HarmonyOS 为 `Image.blur`），省去全分辨率截图开销，代价是关闭切回真实
  上一页时有一个从模糊到清晰的细微跳变。模糊截图无需与上一页像素对齐，
  通常与 `backdropTransition: false` 搭配作为静态氛围背景。

### 系统路由

`router.openURL(url)` 把 URL 交给操作系统解析：注册了该 scheme 的任意 App
都可以响应（`weixin://`、`imeituan://`、`alipay://xxx`、`https://…`）。没有
App 能处理时 Promise 会以宿主错误消息 reject。共享层要求 URL 非空、声明
scheme 且不含首尾空白，并拒绝 `javascript:` 与 `data:`。

三端实现：Android 用 `ACTION_VIEW` 隐式 Intent（直接 `startActivity` 不受
Android 11+ 包可见性限制，无需 `<queries>`；只有 `resolveActivity` 之类的
查询才需要）；iOS 用 `UIApplication.open`（它不需要
`LSApplicationQueriesSchemes`，只有 `canOpenURL` 检查才需要）；HarmonyOS
用 `UIAbilityContext.openLink`。要在系统里注册自己的 scheme：Android 在
`AndroidManifest.xml` 里给目标 Activity 加 `VIEW`/`BROWSABLE` intent-filter，
iOS 在 `Info.plist` 声明 `CFBundleURLTypes`，HarmonyOS 在 `module.json5`
的 ability `skills` 里声明 `uris.scheme`。

外部打进来的 `lynxapp://www.lynxjs.org/<path>?<query>` 深链由三端共同接收。
唯一配置处是 `contracts/deeplinks.json`：

```json
{
  "schemaVersion": 1,
  "scheme": "lynxapp",
  "host": "www.lynxjs.org",
  "defaultBundle": "main",
  "routes": [
    { "path": "/", "bundle": "main" },
    { "path": "/networkinfo", "bundle": "main", "params": { "page": "networkinfo" } }
  ]
}
```

`pnpm native:sync`（包含在 `pnpm build:lynx` 中）校验该文件（scheme/host
格式、path 唯一、映射的 bundle 必须存在于 workspace）并把它分发到三端资源
目录（Android `assets/lynxbundle/`、iOS `lynxbundle/`、HarmonyOS
`rawfile/lynxbundle/`），与 `lynx-bundles.json` 并列；三端宿主运行时读取
同一份映射。解析规则：host 必须与配置一致，path 精确匹配路由表映射到目标
bundle；路由条目可携带静态 `params`，与 URL query 合并（query 优先）；最终
参数注入页面的 `route.params`，与 Navigation 推送页的 init data 结构一致——
`lynxapp://www.lynxjs.org/networkinfo?a=1` 打开 `main` bundle 且
`useRouteParams()` 返回 `{ a: '1', page: 'networkinfo' }`。host 或 path 未
命中时回退 `defaultBundle` 首页（无参数）；其他 scheme 不属于本应用。

三端捕获与消费：Android 在 `AndroidManifest.xml` 注册 `VIEW`/`BROWSABLE`
intent-filter（scheme 取自同一配置，经 Gradle `manifestPlaceholders` 注入），
`MainActivity` 在创建前把解析结果写入标准路由 extras；iOS 在 `Info.plist`
声明 `CFBundleURLTypes`（系统只能按 scheme 级捕获，host 校验在
`SceneDelegate` 内按配置执行）；HarmonyOS 在 `module.json5` 的 `skills`
声明 scheme，`EntryAbility` 的 `onCreate`/`onNewWant` 解析 Want URI。冷启动
时深链页作为根页面打开；应用已在前台时（热深链）三端统一叠加新页面
（Android 新 Activity 实例入栈、iOS push、HarmonyOS push NavDestination），
返回键回到进入前的状态。自定义 scheme 没有所有权验证，其他 App 也能注册
`lynxapp`，冲突时 Android 弹选择框、iOS 行为未定义。

调试入口：`adb shell am start -a android.intent.action.VIEW -d
"lynxapp://www.lynxjs.org/networkinfo?a=1"`、`xcrun simctl openurl
"lynxapp://www.lynxjs.org/networkinfo"`、`hdc shell aa start -U
"lynxapp://www.lynxjs.org/networkinfo"`。旧的 `lynxapp://<bundle>?<query>`
格式（host 即 bundle 名）已移除，此类链接现在按未命中回退首页。

### 状态栏样式

`statusBarStyle` 和 `statusBar.setStyle()` 描述的是状态栏前景，而不是页面背景：

- `dark-content`：深色图标和文字，适用于白色或其他浅色背景；
- `light-content`：白色图标和文字，适用于深色背景。

路由参数决定目标原生页面创建时的初始样式，默认是 `dark-content`；
`statusBar.setStyle()` 通过同一个 `DeviceInfo.setStatusBarStyle` 模块方法动态切换当前页面，
不再存在独立 `StatusBar` NativeModule。三个宿主都保持状态栏背景透明，让 Lynx 页面继续
绘制到系统栏下面。路由 init data 中也包含 `route.statusBarStyle`，业务可以读取并保持自己的视觉状态一致。

### 剪贴板与震动反馈

| 方法 | 说明 |
| --- | --- |
| `clipboard.setString(text)` | 写入系统剪贴板 |
| `clipboard.getString()` | 读取剪贴板文本；为空或不可用时返回 `null` |
| `haptics.impact(style)` | 单击震动；`style` 为 `'light' \| 'medium' \| 'heavy'`，非法取值被共享层拒绝 |

HarmonyOS 剪贴板实现基于 Pasteboard，不声明
`ohos.permission.READ_PASTEBOARD`，也不会触发运行时授权。写入不需要额外授权；读取会先确认
剪贴板包含纯文本，系统不允许读取、内容为空或读取失败时统一返回 `null`。

HarmonyOS 触感反馈基于 Sensor Service Kit 的 Vibrator：light / medium / heavy 分别映射到
soft / sharp / hard 预置效果；设备不支持对应预置效果时降级为 15 / 30 / 60ms 单次振动。
`ohos.permission.VIBRATE` 是普通的系统授权权限，无需运行时弹窗。

### 生物认证 v2

v2 把“认证策略”和“传感器类型”分开：业务选择需要的保证等级，系统在同一次弹窗中使用
设备已配置且满足策略的人脸或指纹。绝大多数设备只有其中一种，业务不应提供“选人脸 / 选指纹”
按钮。`biometryType` 只用于辅助文案，不是传给 `authenticate` 的选择器；Android 无法可靠获知
具体类型，因此可能返回 `unknown`。

| `policy` | 语义 | Android | iOS | HarmonyOS |
| --- | --- | --- | --- | --- |
| `biometricWeak`（默认） | 任一系统认可的生物认证 | `BIOMETRIC_WEAK` | `deviceOwnerAuthenticationWithBiometrics` | ATL2 指纹 / 面容 |
| `biometricStrong` | 强生物认证，不允许锁屏凭据替代 | `BIOMETRIC_STRONG` | 同上（iOS 不暴露强弱等级） | ATL3 指纹 / 面容 |
| `deviceOwnerAuthentication` | 生物认证或系统锁屏凭据 | `BIOMETRIC_WEAK \| DEVICE_CREDENTIAL` | `deviceOwnerAuthentication` | ATL2 指纹 / 面容 / PIN |

```ts
import { biometric } from '@lynx-template/autolink-biometric';

// 静默查询，不显示 UI；应使用与随后认证相同的 policy。
const support = await biometric.checkSupport({ policy: 'biometricWeak' });
// { policy, canAuthenticate, reason, biometryType, deviceCredentialSetup }

const outcome = await biometric.authenticate({
  policy: 'biometricWeak',
  title: '确认身份',       // Android / HarmonyOS 显示；iOS 不显示标题
  reason: '继续本次操作', // iOS localizedReason / Android 描述
  cancelButtonText: '取消',
});

if (outcome.success) {
  // 仅表示本机认证成功。
}
```

取消、失败与系统打断均 resolve 结构化 outcome；参数非法可能同步抛错，传输损坏或宿主未注册
模块会 reject。`success` 恒等于 `code === 'success'`，outcome 会回显实际 `policy`。同一 Lynx 页面
同一时刻只允许一个系统认证 UI，重入返回 `busy`。常见 code 包括 `userCancel`、`systemCancel`、`failed`、
`notEnrolled`、`locked`、`noDeviceCredential` 与 `unavailable`。

`cancelButtonText` 只表示取消 / 导航，不再承担“使用密码”的业务降级含义。需要系统锁屏凭据
时显式选择 `deviceOwnerAuthentication`；需要应用自己的密码流程时，在认证失败或取消后由业务
自行导航。

三端仍保留原有宿主前置条件：Android Activity 必须是 `FragmentActivity` 且库声明
`USE_BIOMETRIC`；iOS 使用 Face ID 时宿主必须声明 `NSFaceIDUsageDescription`；HarmonyOS
模块声明 `ohos.permission.ACCESS_BIOMETRIC`。

**安全边界**：`authenticate` 只做本机在场验证，客户端布尔结果可以被 hook，不能作为服务端
敏感操作凭据。需要服务端校验时使用下面的 v2 挑战签名协议。

### v2 挑战签名（服务端可校验）

v2 不再维护一把隐式固定密钥。每次 `createSigningKey({ scope })` 都创建新的 P-256 密钥并返回
唯一 `keyId`，旧密钥继续可用，业务可安全轮换。`scope` 只能包含 ASCII 字母、数字、点、下划线
和连字符（1..64 字符），应使用不含账号、手机号等个人信息的稳定代号。

```ts
import { biometric } from '@lynx-template/autolink-biometric';

// 注册：服务端挑战可用于尽力而为的密钥证明。
const created = await biometric.createSigningKey({
  scope: 'payments',
  attestationChallenge, // 可选，标准 Base64，解码后 16..128 字节
});
if (created.success) {
  await api.post('/biometric/keys', {
    keyId: created.keyId,
    publicKey: created.publicKey,
    algorithm: created.algorithm,                 // ES256
    signatureEncoding: created.signatureEncoding, // ieee-p1363
    securityLevel: created.securityLevel,
    attestation: created.attestation,
  });
}

// 使用：challenge 由服务端一次性下发；contextHash 是规范业务内容的 SHA-256。
const signed = await biometric.signChallenge({
  keyId: created.keyId!,
  challenge,  // 标准 Base64，解码后 16..64 字节
  contextHash,
  title: '确认支付',
  reason: '确认向商户支付 ¥128.00',
});
if (signed.success) {
  await api.post('/payments/confirm', {
    keyId: signed.keyId,
    challenge,
    contextHash,
    signature: signed.signature,
  });
}
```

另外提供 `getSigningKey({ keyId })` 恢复公钥元数据，以及 `deleteSigningKey({ keyId })` 删除
指定密钥。推荐轮换顺序是“创建新密钥 → 服务端登记并验证 → 服务端切换为 active → 删除旧密钥”；
不要先删旧密钥。`keyNotFound` 表示密钥不存在，或因生物信息重新录入而被平台安全策略作废。

三端协议字节完全一致。共享层在调用原生模块前构造：

```text
ASCII("LYNX_BIOMETRIC_V2\0") || ASCII(keyId) || 0x00 ||
contextHash[32] || challenge[16..64]
```

原生端再次校验域分隔符、`keyId` 和长度后，以 SHA-256 ECDSA 签名。公钥是 Base64 编码的
65 字节非压缩 P-256 点（`0x04 || X || Y`），签名统一为 Base64 编码的 64 字节 IEEE P1363
`r || s`。服务端验签示例：

```ts
import { createPublicKey, verify } from 'node:crypto';

const SPKI_PREFIX = Buffer.from(
  '3059301306072a8648ce3d020106082a8648ce3d030107034200',
  'hex',
);

function verifyBiometricSignature(input: {
  keyId: string;
  publicKey: string;
  contextHash: string;
  challenge: string;
  signature: string;
}): boolean {
  const point = Buffer.from(input.publicKey, 'base64');
  const key = createPublicKey({
    key: Buffer.concat([SPKI_PREFIX, point]),
    format: 'der',
    type: 'spki',
  });
  const payload = Buffer.concat([
    Buffer.from('LYNX_BIOMETRIC_V2\0', 'ascii'),
    Buffer.from(input.keyId, 'ascii'),
    Buffer.from([0]),
    Buffer.from(input.contextHash, 'base64'),
    Buffer.from(input.challenge, 'base64'),
  ]);
  return verify(
    'sha256',
    payload,
    { key, dsaEncoding: 'ieee-p1363' },
    Buffer.from(input.signature, 'base64'),
  );
}
```

| 平台 | 私钥与认证约束 | 元数据 |
| --- | --- | --- |
| Android | AndroidKeyStore，每次签名用 `BiometricPrompt.CryptoObject` 且要求 `BIOMETRIC_STRONG`；重录生物即失效 | 报告 `secureHardware` / `software`；传入证明挑战时返回 Android X.509 证明链 |
| iOS | 真机只接受 Secure Enclave，`biometryCurrentSet \| privateKeyUsage`；仅模拟器允许软件 keychain 密钥 | 报告安全级别；当前不提供证明 |
| HarmonyOS | HUKS 会话 challenge 与 ATL3 生物认证 token 绑定后才可 `finishSession` | 当前安全级别为 `unknown`，不提供证明 |

签名始终要求强生物认证，不接受锁屏密码替代。`attestation` 是尽力而为的注册证据，服务端必须
按平台验证证书链、挑战和应用身份，不能只检查字段存在。服务端还必须确保 nonce 随机、一次性、
短时效，并在验签前确认 `keyId` 属于当前账号且仍为 active；`contextHash` 必须由规范化的完整业务
操作计算，不能只绑定按钮名称或展示文案。


### 相册与文件选择

```ts
interface PickerOptions {
  maxSelection?: number; // 默认 1，统一限制为 1..50 的整数
}

const avatarURIs = await albumUtils.pick();
const attachmentURIs = await fileSystem.pick({ maxSelection: 5 });
await albumUtils.saveToAlbum(avatarURIs[0]); // 把图片存回系统相册
```

两个 pick API 都返回 `Promise<string[]>`。用户取消时解析为空数组；系统能力不可用、参数非法、
权限被拒绝或读取结果失败时 Promise reject。同一类 Picker 同一时间只允许一个活动请求。
`albumUtils.pick` 只显示图片，`fileSystem.pick` 当前不限制文件类型。

`albumUtils.saveToAlbum(uri)` 把一个图片 URI 写入系统相册，`Promise<void>` 在保存完成时
resolve，失败时 reject；平台可能在保存前向用户确认：

- **Android**：`MediaStore` 插入 `Pictures/Lynx`，无需任何权限，但要求 Android 10+；
  更早版本会 reject 并提示需要 Android 10。只接受 `image/*` MIME。
- **iOS**：`PHAssetCreationRequest` 增量写入（add-only），宿主已在 Info.plist 声明
  `NSPhotoLibraryAddUsageDescription`，首次保存时系统弹一次"允许添加照片"；只接受 `file://` URI。
- **HarmonyOS**：`MediaAssetChangeRequest` 由系统弹保存确认框，无需申请媒体权限；
  传入 Picker URI 或应用沙箱内的 `file://` URI 均可。

返回的是平台 URI，不应把它当成跨平台真实路径：Android 返回 `content://` URI，并在内容提供方
支持时取得持久读授权；iOS 会把结果复制到 `Library/Caches/LynxFiles` 后返回 `file://` URI；
HarmonyOS 返回系统 Picker URI，其授权可能随应用进入后台而失效。需要上传或长期保存时，应在
选择完成后尽快读取或复制；iOS 缓存文件也可能被系统清理。

系统 Picker / 相册写入的权限边界如下：

| 平台 | 实现与低版本回退 | 相册 / 文件权限 |
| --- | --- | --- |
| Android | 图片优先 Android Photo Picker；不可用时回退 Storage Access Framework。文件始终使用 `ACTION_OPEN_DOCUMENT`。存图走 `MediaStore`（Android 10+） | 都是用户逐项授权，不声明 `READ_MEDIA_IMAGES` 或 `READ_EXTERNAL_STORAGE`；即使本工程最低 Android 7.0 也不需要广泛存储权限 |
| iOS 14+ | 图片使用 `PHPickerViewController`；文件使用 `UIDocumentPickerViewController`。存图走 add-only `PHAssetCreationRequest` | 选图 / 选文件无需运行时授权；存图只需 `NSPhotoLibraryAddUsageDescription`（已在宿主声明） |
| iOS 13 | 图片回退 `UIImagePickerController`（仅支持单选）；文件仍使用 `UIDocumentPickerViewController` | 只有图片回退需要 `NSPhotoLibraryUsageDescription` 和 Photos 运行时授权；文件不需要 |
| HarmonyOS | 图片使用 `PhotoViewPicker`；文件使用 `DocumentViewPicker`。存图走 `MediaAssetChangeRequest` 系统确认框 | Picker 接口本身无需申请相册或文件权限，由用户选择行为授予临时 URI 访问 |

因此“高版本系统 Picker 无需广泛权限”是对的，但“所有低版本都必须申请权限”并不准确：
本实现只有 iOS 13 的系统相册回退需要 Photos 权限。若业务绕过 Picker，直接枚举公共媒体库或
文件系统，则是另一种访问模型，需要按平台和系统版本另外声明权限。

### 文件操作

`FileSystem` 同时承载系统文件选择器（`pick`）和 URI 文件操作，直接操作 Picker 返回的 URI，
不要求业务把 `content://` 或系统媒体 URI 转成真实路径：

```ts
interface FileInfo {
  uri: string;
  name: string;
  mimeType: string | null;
  size: number | null;
}

const [uri] = await fileSystem.pick();
if (uri) {
  const info = await fileSystem.stat(uri);
  const cachedURI = await fileSystem.copyToCache(uri);
  const text = await fileSystem.readText(uri); // 默认最多读取 1 MiB
  const base64 = await fileSystem.readBase64(uri, { maxBytes: 2 * 1024 * 1024 });
  const bytes = await fileSystem.readArrayBuffer(uri); // ArrayBuffer，默认上限 5 MiB
  console.info(`${info.name} ${info.mimeType} ${cachedURI} ${text.length} ${base64.length} ${bytes.byteLength}`);
}
```

写入、删除与列目录只作用于应用缓存沙箱（`<cache>/LynxFiles`），`uri` 传相对沙箱根的
路径即可，写入会自动创建父目录：

```ts
interface WriteFileOptions {
  append?: boolean; // 追加写，默认覆盖
}
interface CacheEntry {
  name: string;
  uri: string;
  isDirectory: boolean;
  size: number | null; // 目录为 null
}

const root = await fileSystem.cacheDir(); // 沙箱根目录 file:// URI
const logURI = await fileSystem.writeText('demo/hello.txt', 'hello lynx\n', { append: true });
const blobURI = await fileSystem.writeArrayBuffer('demo/blob.bin', bytes.buffer);
const entries = await fileSystem.listDir('demo'); // 平铺列举，按名称排序
await fileSystem.delete('demo'); // 目录递归删除
```

| 方法 | 返回值 | 说明 |
| --- | --- | --- |
| `fileSystem.pick(options?)` | `Promise<string[]>` | 打开系统文件选择器；取消时解析为空数组 |
| `fileSystem.stat(uri)` | `Promise<FileInfo>` | 获取名称、MIME 和字节数；内容提供方无法确定时相应字段为 `null` |
| `fileSystem.copyToCache(uri)` | `Promise<string>` | 流式复制到应用缓存，返回 `file://` URI；缓存仍可能被系统清理 |
| `fileSystem.readText(uri, options?)` | `Promise<string>` | 严格按 UTF-8 解码；默认上限 1 MiB |
| `fileSystem.readBase64(uri, options?)` | `Promise<string>` | 返回标准 Base64；默认源文件上限 5 MiB |
| `fileSystem.readArrayBuffer(uri, options?)` | `Promise<ArrayBuffer>` | 在 JS 侧解码 Base64 得到 ArrayBuffer；默认源文件上限 5 MiB |
| `fileSystem.writeText(uri, contents, options?)` | `Promise<string>` | 把 UTF-8 文本写入缓存沙箱，返回 `file://` URI；`append` 为真时追加 |
| `fileSystem.writeBase64(uri, base64, options?)` | `Promise<string>` | 解码 Base64 后写入缓存沙箱，返回 `file://` URI |
| `fileSystem.writeArrayBuffer(uri, data, options?)` | `Promise<string>` | 在 JS 侧编码 Base64 后写入，与 `writeBase64` 同上限 |
| `fileSystem.delete(uri)` | `Promise<void>` | 删除沙箱内文件或目录（目录递归）；删除沙箱根即清空缓存 |
| `fileSystem.listDir(uri)` | `Promise<CacheEntry[]>` | 平铺列出沙箱内目录，按名称排序 |
| `fileSystem.cacheDir()` | `Promise<string>` | 返回缓存沙箱根目录的 `file://` URI |

`maxBytes` 必须是 `1..20 MiB` 的整数，限制的是编码前源文件大小。Base64 会额外膨胀约三分之一，
`readArrayBuffer` 复用同一条 Base64 通道再在 JS 侧解码，因此开销与 `readBase64` 相同；
大文件上传不应经过 JS/Base64 bridge，应由网络层直接流式读取 URI。Android 支持 Picker 的
`content://` 和缓存 `file://` URI；iOS Picker 已先复制到缓存，因此 `FileSystem` 接受 `file://`；
HarmonyOS 直接使用 Picker URI。该模块沿用 Picker 授予的访问范围，不新增媒体或存储权限。

写入 / 删除 / 列目录的寻址同样简单：`uri` 既可以是相对沙箱根的路径（`''` 或 `'.'` 即根目录），
也可以是 `copyToCache` / `writeText` / `cacheDir()` 返回的 `file://` URI。规范化后落在沙箱外
（`..` 逃逸、沙箱外绝对路径、`content://` 等）会直接 reject；单次写入上限 20 MiB（与读取一致），
iOS Picker 的副本也落在 `LynxFiles`，因此三端 `pick` 的结果都能统一列举与清理。

`readBase64` / `readArrayBuffer` 同样适用于 `albumUtils.pick()` 返回的图片 URI——三端选图
URI 都能被 `FileSystem` 直接读取，因此“选图 → 转 Base64 / ArrayBuffer”是现成能力：

```ts
const [photoURI] = await albumUtils.pick();
if (photoURI) {
  const base64 = await fileSystem.readBase64(photoURI); // 默认上限 5 MiB
  const bytes = await fileSystem.readArrayBuffer(photoURI); // ArrayBuffer
}
```

### 扫码

`Scanner` 提供两级识码 API：`scan()` 拉起全屏扫码页，`scanFromImage(uri)` 对
本地图片识码（例如 `albumUtils.pick()` 的返回值），全程不进入 JS 的位图通道：

```ts
import { scanner } from '@lynx-template/autolink-scanner';

const outcome = await scanner.scan();
if (outcome.success) {
  // { code: 'success', content: 'https://…', format: 'qr_code', message: '' }
} else if (outcome.code === 'permissionDenied') {
  // 引导用户去系统设置开启相机（Android / iOS 独有分支）
}

const [photoURI] = await albumUtils.pick();
if (photoURI) {
  const decoded = await scanner.scanFromImage(photoURI);
  // 图片里没有码时 resolve 'noCodeFound'，而不是 reject
}
```

`scan` 与 `scanFromImage` 都 resolve 结构化 outcome：用户关闭扫码页
（`userCancel`）、相机权限被拒（`permissionDenied`，HarmonyOS 不会出现）、
无相机硬件（`unavailable`）、同一页面并发第二个请求（`busy`）和图片无码
（`noCodeFound`，仅 `scanFromImage`）都是正常业务分支，只有参数非法或宿主
未注册模块才 reject。`content` / `format` 仅在 `code === 'success'` 时非空。
`format` 是三端统一命名（`qr_code`、`code128`、`ean_13`、`data_matrix` 等）；
HarmonyOS 额外报告系统特有的 `multifunctional`，iOS 按系统行为把 UPC-A
回报为 `ean_13`。**扫码结果是不可信输入**：不要直接 `eval` 或无条件跳转
`content` 中的 URL，应由业务确认或交服务端校验。

三端实现与权限边界：

| 平台 | `scan`（相机） | `scanFromImage`（图片） | 权限 |
| --- | --- | --- | --- |
| Android | autolink 库内全屏 `ScannerActivity`：CameraX Preview + ImageAnalysis，ML Kit bundled 模型离线识码（不依赖 Google Play Services），带取景框 / 手电筒 / 关闭按钮 | ML Kit `InputImage.fromFilePath` 解码 `content://` / `file://` URI | `CAMERA`：库 manifest 声明并合并进宿主，运行时授权由扫码页自己发起；识码被拒 resolve `permissionDenied` |
| iOS | autolink 库内全屏 VC：`AVCaptureSession` + `AVCaptureMetadataOutput`，同样的取景框 / 关闭 UI | Vision `VNDetectBarcodesRequest` 解码 `file://` 图片（相册选择已复制进缓存） | 宿主 Info.plist 声明 `NSCameraUsageDescription`（已在宿主声明）；`AVCaptureDevice` 授权被拒 resolve `permissionDenied` |
| HarmonyOS | Scan Kit 默认系统扫码页 `scanBarcode.startScanForResult` | Scan Kit `detectBarcode.decode`（`InputImage` 直接接受 URI） | 均无需相机权限：系统扫码页运行在系统侧，图片识码是纯本地解码 |

HarmonyOS 的用户取消以 Scan Kit 错误码 `1000500002`
（`scanCore.ScanErrorCode.SCAN_SERVICE_CANCELED`）识别并映射为 `userCancel`。

### 系统分享

`Share` 调起系统分享面板发送纯文本、链接与本地文件（`screenshot.capture`、
`fileSystem.copyToCache` 或 `albumUtils.pick` 的产物），取消是正常业务分支：

```ts
import { share } from '@lynx-template/autolink-share';

const outcome = await share.open({
  title: 'Lynx 截图',                 // 邮件类目标的主题 / 面板标题
  text: '来自 Lynx Template 的分享',  // 纯文本，≤10000 字符
  url: 'https://lynxjs.org',          // 链接：必须带 scheme，拒绝 javascript:/data:
});
// { success, code: 'sent' | 'dismissed' | 'busy', activityType, message }

const shot = await screenshot.capture({ format: 'jpeg' });
await share.open({ files: [shot.uri] }); // files 接受 1-9 个本地 URI
```

`text` / `url` / `files` 至少一项非空，否则共享层直接抛错；`files` 只接受
`file://`（Android 另接受 Picker 的 `content://`），`http(s)://` 会被拒绝并提示
先经网络层下载——与 `audioPlayer` 的“仅本地”原则一致。Android 没有独立的链接
字段，`url` 合并进 `EXTRA_TEXT`；iOS 把文本、链接与文件作为独立 activity item；
HarmonyOS 的链接以 `HYPERLINK` 记录分享（`text` 作为描述），与文件混合时链接
降级忽略（记录类型不可混）。

**结果保真度三端不同**，`success` 恒等于 `code === 'sent'`：

| code | Android | iOS | HarmonyOS |
| --- | --- | --- | --- |
| `sent` | 用户在 chooser 选中目标（`EXTRA_CHOSEN_COMPONENT`，`activityType` = 目标包名） | `completed = true`（`activityType` = `UIActivityType`） | 面板正常关闭即 resolve `sent`：Share Kit 只有 `dismiss` 事件，不区分送达与取消 |
| `dismissed` | chooser 未选中即关闭（best-effort：宿主 Activity resume 后的宽限窗口内仍无选中广播；平台本身不上报取消） | `completed = false` | 不产生 |
| `busy` | 同一页面已有进行中的分享，三端一致 | 同左 | 同左 |

参数非法、无宿主 Activity/窗口、面板拉不起来才 reject。同一页面同时只允许一个
进行中的分享。

| 平台 | 实现 |
| --- | --- |
| Android | `ACTION_SEND` / `ACTION_SEND_MULTIPLE` + `Intent.createChooser`（携带 chosen-component PendingIntent，API 22+）；沙箱 `file://` 经库内 FileProvider（`${applicationId}.lynx.share.fileprovider`，暴露 cache/files 根）转 content URI，Picker `content://` 直传；`ClipData` + `FLAG_GRANT_READ_URI_PERMISSION` 给目标应用临时读授权 |
| iOS | `UIActivityViewController`，从 LynxView 顶层 VC present；iPad 以无箭头 popover 锚定 LynxView 中心；`title` 经 KVC `subject` 传给邮件类目标 |
| HarmonyOS | Share Kit `systemShare.SharedData` + `ShareController.show`（`PLAIN_TEXT` / `HYPERLINK` / 按文件后缀映射的 UTD 记录，多文件 `BATCH` 选择）；面板运行在系统侧，无需权限；文件须在应用沙箱内（Picker URI 先 `fileSystem.copyToCache`） |

### 音频播放

`AudioPlayer` 播放本地音频文件，「选择 → 播放」的标准管线是 `fileSystem.pick()`
（或 `albumUtils.pick()`）返回的 URI 直接交给 `audioPlayer.create()`；Android 接受
`file://` 与 `content://`，iOS / HarmonyOS 接受 `file://`（Harmony 模块内部 open 转 fd，
fd 在整个播放期间保持打开）。共享层拒绝 `http(s)://` 并提示仅支持本地文件。

```ts
import { audioPlayer } from '@lynx-template/autolink-audio-player';

const player = audioPlayer.create({
  uri: pickedURI,
  usage: 'media',        // 'media' | 'ambient' | 'alarm' | 'notification'
  autoPlay: true,
});
await player.created;    // 原生 prepare 完成后 resolve；失败 reject
player.addEventListener('state', (event) => {
  // event.state: 'loading' | 'paused' | 'playing' | 'stopped'
  // event.interruption?: 'pause' | 'duck' | 'resume' | 'unduck'（音频焦点）
});
player.addEventListener('progress', (event) => {
  // event.positionMs / event.durationMs，默认 250ms 节流
});
await player.play();
await player.seek(30_000);
const props = await player.getProps();
player.destroy();        // release + 移除监听，幂等
```

`create()` 失败按前缀分类：`file-not-found`（文件不存在或无授权）、
`unsupported-format`（解码 / 编码器不支持，prepare 失败）、`read-failed`（IO 错误）。
播放中错误以 `error` 事件回传后进入 `paused`；播完发一个 `end` 事件并回到
`paused`（位置停在末尾，再次 `play` 从头开始）。`setVolume` 只是单实例增益（0..1，
用于混音 / 淡入淡出），不触碰系统音量——三端系统流音量均不在模块能力内。

四种 `usage` 在创建时声明且不可中途切换（换流 = 换音量曲线与焦点策略，
Harmony 还要求回到 initialized 状态重设，业务应 release 后重建）：

| `usage` | Android | iOS | HarmonyOS |
| --- | --- | --- | --- |
| `media`（默认） | `USAGE_MEDIA`（媒体音量），请求永久焦点 | `.playback`：无视静音开关，激活即打断其他播放 | `STREAM_USAGE_MUSIC` |
| `ambient` | 媒体音量，不请求焦点、不打断别人 | `.ambient`：**跟随静音开关**，与其他音频混音 | `STREAM_USAGE_MUSIC`，不注册焦点 |
| `alarm` | `USAGE_ALARM`（闹钟音量），transient 焦点 | `.playback` | `STREAM_USAGE_ALARM` |
| `notification` | `USAGE_NOTIFICATION`（通知音量），may-duck 焦点，受 DND 约束 | `.ambient` | `STREAM_USAGE_NOTIFICATION_RINGTONE` |

`ringtone` / `voiceCall` 两个流刻意不支持：iOS 来电铃声属于 CallKit、通话音轨涉及
EARPIECE / SCO 路由，播放器模块无法给出三端一致语义，共享层直接拒绝。

打断语义：焦点丢失时原生自动暂停并上报 `interruption: 'pause'`；transient 打断结束
自动恢复播放并上报 `resume`；导航播报类 may-duck 打断由原生自动压低 / 恢复音量
（`duck` / `unduck`，仅 Android 会出现）。HarmonyOS 的焦点由 AVPlayer 按 StreamUsage
自动管理（系统已自动暂停 / 压低），`media` / `alarm` / `notification` 实例注册
`audioInterrupt` 回调把同样的语义上报为 `interruption`（BEGIN → `pause` /
duck hint → `duck`，END + resume hint → `resume`）。`ambient` 实例不参与焦点，
永远收不到打断事件。

| 平台 | 播放器 | 速率 | 说明 |
| --- | --- | --- | --- |
| Android | `MediaPlayer`（无三方依赖），全部操作序列化到主线程 Handler | `PlaybackParams.setSpeed`，0.25–4 连续 | 焦点手动管理：`AudioFocusRequest` 按流构造 attributes，LOSS 暂停、CAN_DUCK 降至 20% |
| iOS | `AVAudioPlayer`（同步初始化，时长即得） | `enableRate` + `rate`，0.25–4 连续 | 打断经 `AVAudioSession` 中断通知；`shouldResume` 时自动恢复；播放计数归零后 deactivate 通知其他 App |
| HarmonyOS | `media.AVPlayer`，`audioRendererInfo` 在 initialized 态设置 | 离散档位 0.5–3.0（0.5/0.75/1.0/1.25/1.5/1.75/2.0/3.0），就近取档 | `timeUpdate` 回调按 `progressIntervalMs` 节流；`endOfStream` 映射为 `end` 事件 + `paused`；seek/setSpeed/setVolume 为 void 调用（结果经 seekDone/speedDone/volumeChange 事件） |

页面销毁时三端统一 stop + release 全部实例（Android `destroy()`、iOS `-destroy`、
Harmony `LynxViewClient.onDestroy()`），Harmony 连带关闭 fd。边界：不播放网络源、
不做后台播放（Android 前台服务 / iOS `UIBackgroundModes` / Harmony continuous task
属宿主配置）、不提供应用内置资源播放（`res/raw` / bundle resource / rawfile）与
系统音量控制。

### 截图

`Screenshot` 把视图快照编码为 PNG/JPEG 写入应用缓存目录（`<cache>/LynxImages/`），
返回 `file://` URI 与像素尺寸；产物可以直接交给 `AlbumUtils.saveToAlbum` 存回相册：

```ts
import { albumUtils } from '@lynx-template/autolink-album-utils';
import { screenshot } from '@lynx-template/autolink-screenshot';

const card = await screenshot.capture({
  idSelector: 'demo-card', // 省略时截取整个 LynxView
  format: 'jpeg',
  quality: 90, // 仅 JPEG 使用；1-100，默认 80
  fileName: 'demo-card', // 缓存文件名后缀，默认 screenshot
});
// { uri: 'file:///…/LynxImages/<uuid>-demo-card.jpg', width: 1080, height: 640 }

const page = await screenshot.capturePage(); // 当前原生页面，选项同上（不含 idSelector）
await albumUtils.saveToAlbum(page.uri);
```

`capture` 三端都支持通过 `idSelector` 截取页内某个元素——Lynx 元素设置
`idSelector` 属性后即可被原生查找。Android 上被视图扁平化（LynxFlattenUI、无平台
View）的元素会回退为整视图绘制后按元素 `getBoundingClientRect()` 裁剪。HarmonyOS 4.2 由
`LynxContext.getComponentSnapshot(idSelector)` 直接解析 Lynx 根组件或目标元素，不再依赖
宿主容器 ID。

`capturePage` 截取的是「当前原生页面」的合成像素，等价于 Android 的窗口
PixelCopy：包含 LynxView 之外的原生内容（原生标题栏、叠加层等），且不需要任何
截屏权限。

| 行为 | Android | iOS | HarmonyOS |
| --- | --- | --- | --- |
| `capture` 默认 | `LynxView.draw(Canvas)` 到 Bitmap | `drawViewHierarchyInRect`，未上屏时回退 `layer.renderInContext` | `LynxContext.getComponentSnapshot('')` 截 Lynx 根组件 |
| `capture` + `idSelector` | `LynxView.findViewByIdSelector()`，扁平化元素回退整视图绘制 + `getBoundingClientRect()` 裁剪 | `LynxView viewWithIdSelector:` | `LynxContext.getComponentSnapshot(idSelector)` |
| `capturePage` | `PixelCopy.request(window, …)`；API 24/25 回退到绘制 decor view | key window 快照 | 当前 Lynx window 的 `snapshot()` |

JPEG 输出先合成白色底（JPEG 没有透明通道）；视图绘制在主线程执行，编码与文件
IO 在后台线程完成。目标未布局（宽高为 0）、`idSelector` 无匹配或 LynxView 尚未
attach 时 reject。

### 图片工具

`ImageTooling` 提供图片信息、缩放、单区域裁剪、多图拼接/叠加与 EXIF 管理。输入是
`albumUtils.pick()`、`fileSystem` 或 `screenshot` 产出的平台图片 URI，位图不经过 JS bridge：

```ts
import { imageTooling } from '@lynx-template/autolink-image-tooling';

const info = await imageTooling.info(uri);
// { width, height, mimeType, sizeBytes }（尺寸已应用 EXIF 方向）

const result = await imageTooling.compress({
  uri,
  maxWidth: 1024,
  maxHeight: 1024, // 等比缩到矩形框内，不放大小图；两个都省略时按原尺寸重编码
  quality: 80,     // 仅 JPEG 使用，1-100，默认 80
  format: 'jpeg',  // 或 'png'（保留透明通道，忽略 quality）
});
// { uri: 'file:///…/LynxImages/<uuid>-compressed.jpg', width, height, sizeBytes }

// 坐标基于应用 EXIF 方向后的显示像素；裁剪后再按 maxWidth/maxHeight 等比缩小。
const crop = await imageTooling.crop({
  uri,
  x: 100,
  y: 60,
  width: 640,
  height: 480,
  maxWidth: 320,
  maxHeight: 320,
  format: 'png',
});

const row = await imageTooling.compose({
  images: [uri, crop.uri],
  layout: 'horizontal', // 也可为 vertical
  spacing: 12,
  maxWidth: 1200,
  maxHeight: 800,
});

const overlay = await imageTooling.compose({
  images: [uri, { uri: crop.uri, x: 24, y: 24, opacity: 0.7 }],
  layout: 'overlay',
  maxWidth: 1024,
  maxHeight: 1024,
  format: 'png',
});

const exif = await imageTooling.readExif(uri);
// { tags: { Make, Model, DateTimeOriginal, ... }, gps: { latitude, longitude, altitude? } | null }

const tagged = await imageTooling.writeExif({
  uri,
  tags: { Software: 'lynx-template', ImageDescription: 'processed' },
  gps: { latitude: 1.23, longitude: 103.45 },
});

// null 删除单个字段；gps: null 删除完整 GPS 分区。源文件不会被原地修改。
const privateCopy = await imageTooling.writeExif({
  uri: tagged.uri,
  tags: { ImageDescription: null },
  gps: null,
});

// 重新编码正向像素，删除全部 EXIF/GPS。
const scrubbed = await imageTooling.removeExif({ uri: privateCopy.uri });
```

横拼按从左到右、顶部对齐，竖拼按从上到下、左侧对齐；叠加模式以 `(0, 0)` 为画布
原点，后面的图层覆盖前面的图层。`maxWidth` / `maxHeight` 作用于完整裁剪结果或完整拼图，
始终保持比例且不放大小图。一次拼图允许 1-16 张图片。

`readExif()` 将 GPS 统一返回为有符号十进制度数。`writeExif()` 保持源编码与未修改的元数据，
在缓存里生成副本；tag 的 `null` 删除该 tag，`gps: null` 删除全部 GPS 字段。
`removeExif()` 则通过解码/重编码删除全部 EXIF/GPS，像素方向会被固定为正向。跨端支持的
tag 白名单由包导出的 `EXIF_TAGS` 给出，包括 Orientation、相机/镜头、拍摄时间、曝光参数、
描述、作者与版权等字段。GPS 属于敏感信息，对外分享前可优先调用 `gps: null` 或
`removeExif()`。

所有写操作都在与 Screenshot 相同的缓存目录（`<cache>/LynxImages/`）创建新文件，源 URI
不会被原地修改；产物可以直接渲染、交给 `fileSystem` 读取或用
`albumUtils.saveToAlbum` 存回相册。JPEG 输出把透明像素显式合成到白底；超过 50 MP 的
输入/输出或单边超过 16,384 px 的输出会 reject。Android 接受 `content://` / `file://`，
iOS 接受 `file://`；HarmonyOS 可读 Picker/file URI，但 EXIF 修改要求 `file://`。
该模块不新增任何权限。

| 平台 | 实现 |
| --- | --- |
| Android | `BitmapFactory` / `Canvas` + AndroidX `ExifInterface`；`ContentResolver` 读取 `content://` / `file://` |
| iOS | ImageIO 读取方向/元数据与写 EXIF，UIKit 裁剪、合成和 JPEG/PNG 编码；仅 `file://` |
| HarmonyOS | ImageKit `ImageSource` / `PixelMap` / `ImagePacker`；Picker 与 `file://` URI，EXIF 修改仅 `file://` |

### 设备信息、显示宽度与亮度

`Device` 的 `deviceInfo` 返回设备与应用事实，也按需读取当前安全区和设置状态栏；
`display` 提供三种
宽度与亮度/常亮控制。按需 API 都在调用时现查，旋转、折叠/展开、多窗口拖拽与配置变更后
立即反映最新值：

```ts
import {
  deviceInfo,
  display,
  safeArea,
  statusBar,
} from '@lynx-template/autolink-device';

const info = await deviceInfo.getInfo();
// { model, manufacturer, osVersion, osApiLevel, appVersion, appBuild,
//   density, locale, isTablet, isFoldable }

const insets = await safeArea.getInsets(); // { top, right, bottom, left }
await statusBar.setStyle('light-content');

const screen = await display.screenWidth();     // 整屏宽度
const window = await display.windowWidth();     // 当前窗口宽度（分屏/折叠时小于屏幕宽）
const view = await display.lynxViewWidth();     // 当前 LynxView 宽度；未布局完成时为 0

const brightness = await display.getBrightness(); // 当前亮度 0..1
await display.setBrightness(0.8);                 // 设置窗口亮度（0..1）
await display.setKeepScreenOn(true);              // 页面可见期间保持屏幕常亮
```

所有宽度都是 Lynx 逻辑像素（Android dp / iOS pt / HarmonyOS vp），与 Lynx 布局
单位一致；`display.lynxViewWidth()` 在 LynxView 尚未 attach 时 reject，布局未完成
时解析为 `0`，业务可据此决定延后查询。

亮度是**窗口级**语义：设置只在本应用/窗口可见期间生效，退出后系统自动恢复原亮度，
三端都无需任何权限（Android 修改系统级亮度需要 `WRITE_SETTINGS` 特殊授权，模板
不采用）。读取时若本窗口未单独设置过亮度，则回落为系统亮度。`setBrightness` 的
取值必须在 0..1（共享层先行校验），无宿主窗口（Android 无 Activity、HarmonyOS 无
UIAbilityContext）时命令 reject。`setKeepScreenOn(true)` 覆盖视频播放页的常亮需求，
再次传 `false` 恢复系统默认息屏行为。

| 字段 / 方法 | Android | iOS | HarmonyOS |
| --- | --- | --- | --- |
| `model` | `Build.MODEL` | `utsname.machine` | `deviceInfo.productModel` |
| `manufacturer` | `Build.MANUFACTURER` | `Apple` | `deviceInfo.brand` |
| `osVersion` | `Build.VERSION.RELEASE` | `UIDevice.systemVersion` | `deviceInfo.osFullName` |
| `osApiLevel` | `Build.VERSION.SDK_INT` | `null` | `deviceInfo.sdkApiVersion` |
| `appVersion` / `appBuild` | `PackageInfo.versionName` / 长版本号 | `CFBundleShortVersionString` / `CFBundleVersion` | `BundleInfo.versionName` / `versionCode` |
| `density` | `DisplayMetrics.density` | `UIScreen.scale` | `display.densityPixels` |
| `locale` | `Locale.toLanguageTag()` | `NSLocale.localeIdentifier` | `i18n.System.getSystemLocale()` |
| `isTablet` | `smallestScreenWidthDp >= 600` | `UIUserInterfaceIdiomPad` | `deviceType === 'tablet'` |
| `isFoldable` | 铰链角度传感器特性（API 30+） | 恒为 `false` | `display.isFoldable()` |

### 轻提示（Toast）

`Toast` 提供一次性轻提示，业务不再需要在 bundle 里挂 `<ToastHost />` 组件；新 toast 替换旧
toast，不排队。`success` / `error` / `info` 在 Android 和 iOS 上显示彩色圆形图标（`✓` / `✕` / `i`），HarmonyOS 以 `✓` / `✕` 文本前缀呈现（`info` 无前缀），`showIcon: false` 可关闭：

```ts
import { toast } from '@lynx-template/autolink-toast';

await toast.show('Saved', { type: 'success', durationMs: 2000 });
await toast.info('Picked Apple');
toast.error('Network unreachable').catch(() => {});
```

三端的气泡都绘制在应用自己的窗口内，不经过系统 Toast/通知管线，因此样式完全自定义、
不受系统主题影响，并且**不需要通知权限**（Android 系统 Toast 经由 NotificationManagerService
投递，通知被禁用或未授权 `POST_NOTIFICATIONS` 时会被静默丢弃，自绘视图没有这个问题）。

完整选项（`ToastOptions`）：`type`（`'info' | 'success' | 'error'`，决定内置图标）、
`showIcon`（默认 `true`）、`backgroundColor` 与 `textColor`（`#RRGGBB` / `#AARRGGBB`）、
`durationMs`（默认 2000，允许 500–10000；Android / iOS 严格遵守，HarmonyOS 收敛到
1500–10000）。消息最长 200 字符。

| 平台 | 实现 |
| --- | --- |
| Android | 自绘气泡加到宿主 Activity 的 DecorView（底部居中，浮于 LynxView 之上） |
| iOS | 自绘气泡挂在 LynxView 所在 window / 前台 key window |
| HarmonyOS | `UIContext.getPromptAction().showToast()`（ArkUI 窗口内 Toast，支持背景/文字色，图标以 `✓`/`✕` 文本前缀呈现） |
| `screenWidth()` | `LynxContext.getScreenMetrics()` | `UIScreen.mainScreen.bounds` | `display.getDefaultDisplaySync()` |
| `windowWidth()` | 宿主 Activity 的 `WindowMetrics` | LynxView 所在 window / 前台 key window | 主窗口 `windowRect` |
| `lynxViewWidth()` | `LynxContext.getLynxView()` | `LynxContext.getLynxView()` | 宿主经 `onAreaChange` 实测上报 |
| `getBrightness()` | 窗口 `screenBrightness`，否则系统亮度 /255 | `UIScreen.mainScreen.brightness` | 窗口 `brightness`，否则 `display…brightness` |
| `setBrightness(v)` | 窗口 `WindowManager.LayoutParams.screenBrightness` | `UIScreen.mainScreen.brightness = v` | `window.setWindowBrightness(v)` |
| `setKeepScreenOn(b)` | `FLAG_KEEP_SCREEN_ON` add/clear | `UIApplication.idleTimerDisabled` | `window.setKeepScreenOn(b)` |

### 运行时权限

`Permissions` 提供跨端统一的运行时权限查询与申请，覆盖通知、相机、相册与麦克风。
`check` 只读状态不弹窗；`request` 在未授权时弹出系统申请框并返回最终状态——用户拒绝
**resolve** 为 `denied` 而不是 reject，只有参数非法或宿主未注册模块才 reject：

```ts
import { permissions } from '@lynx-template/autolink-permissions';

const state = await permissions.check('notifications');
// { status: 'granted' } | 'limited' | 'denied' | 'notDetermined' | 'restricted'

const after = await permissions.request('camera');
if (after.status === 'granted') { /* ... */ }
```

状态语义（`PermissionStatus`）：`granted` 已授权；`limited` 仅相册——Android 14+ 与
iOS 14+ 的"部分照片"授权；`denied` 已拒绝；`notDetermined` 从未申请过（申请必弹窗）；
`restricted` 受系统策略限制（家长控制 / MDM）。平台差异：**Android 无法区分「未申请」
与「拒绝后不再询问」，从不返回 `notDetermined`**，`denied` 之后 `request` 仍可能弹窗；
iOS 一旦 `denied` 只能去系统设置；HarmonyOS 同样把未授权统一报告为 `denied`。

| 平台 | 实现 |
| --- | --- |
| Android | 运行时权限走无头 androidx Fragment 承接弹窗（宿主 Activity 需为 `FragmentActivity`，与 Biometric 相同）；通知在 13+ 走 `POST_NOTIFICATIONS`，12 及以下只读应用级通知开关；相册按系统版本映射 `READ_MEDIA_IMAGES` / `READ_MEDIA_VISUAL_USER_SELECTED`（34+，报告 `limited`）/ `READ_EXTERNAL_STORAGE`（24–32） |
| iOS | 通知 `UNUserNotificationCenter`；相机 `AVCaptureDevice`；相册 `PHPhotoLibrary`（14+ 访问级别 API，可报告 `limited`）；麦克风 `AVAudioSession`；宿主 `Info.plist` 需声明对应 usage 描述键 |
| HarmonyOS | 相机 / 相册 / 麦克风走 `abilityAccessCtrl`（entry 的 `requestPermissions` 需声明 `ohos.permission.CAMERA` / `READ_IMAGEVIDEO` / `MICROPHONE`）；通知走 `isNotificationEnabled` / `requestEnableNotification` 弹窗 |

### 本地通知

`LocalNotification` 通过系统通知中心发送本地通知（立即或 `delayMs` 延迟），并按 id 取消。
**权限申请不在这个模块里**——先用 `permissions.request('notifications')` 申请；未授权时
`notify` resolve 为 `permissionDenied`（不会静默丢弃后假装成功）：

```ts
import { localNotification } from '@lynx-template/autolink-local-notification';
import { permissions } from '@lynx-template/autolink-permissions';

await permissions.request('notifications');
const outcome = await localNotification.notify({
  id: 'order-1001',
  title: '订单已发货',
  body: '预计明天送达',
  delayMs: 5000,        // 可选：延迟发送，0 / 缺省为立即
  sound: true,          // 可选：默认播放系统通知音
});
// { success: true, code: 'success', message: '' }

await localNotification.cancel('order-1001'); // 取消排期与已送达
await localNotification.cancelAll();          // 清除本应用全部通知
```

`id` 由业务自定义且稳定：复用同一 id 会替换上一条；`delayMs` 上限 7 天。平台差异：
Android 的延迟通知经 `AlarmManager` 排期，**App 进程被杀后仍会送达**（精确闹钟不可用时
退化为窗口闹钟）；iOS 经 `UNNotificationRequest` 触发器排期，且前台时以横幅展示；
HarmonyOS 的延迟通知是进程内定时器，**不保证跨进程存活**，`cancelAll` 也只覆盖本实例
发送过的通知。

| 平台 | 实现 |
| --- | --- |
| Android | 框架 `Notification.Builder` + 单一渠道 `lynx.local`；延迟经 `AlarmManager`（`ScheduledNotificationReceiver`，manifest 声明）；排期 id 存 `SharedPreferences`，进程重启后 `cancelAll` 仍能清掉待发闹钟 |
| iOS | `UNUserNotificationCenter`：`addNotificationRequest` + `UNTimeIntervalNotificationTrigger`；`willPresent` delegate 使前台展示横幅（14+ banner/list/sound，13 alert/sound） |
| HarmonyOS | `notificationManager.publish`（`SERVICE_INFORMATION` slot）+ 进程内 `setTimeout` 延迟；字符串 id 以确定性哈希映射为数字 id |

### 电量

`Device` 的 `battery` 按需读取当前电量与充电状态，三端均免权限：

```ts
import { battery } from '@lynx-template/autolink-device';

const info = await battery.getInfo();
// { level: 0.85, charging: true }
// 模拟器 / 无电池设备上 level 为 null
```

`level` 统一为 0..1；`charging` 表示已接入电源（充电中或已充满）。iOS 模拟器读不到
电量（`level: null`）。模板只提供快照查询，需要电量变化通知时由原生宿主自行扩展。

| 平台 | 实现 |
| --- | --- |
| Android | 粘性 `ACTION_BATTERY_CHANGED` 广播现查（无需注册 receiver）：`EXTRA_LEVEL/EXTRA_SCALE` 与 `EXTRA_STATUS` |
| iOS | `UIDevice.batteryLevel` / `batteryState`；调用前自动开启 `batteryMonitoringEnabled` |
| HarmonyOS | `@ohos.batteryInfo` 的 `batterySOC` / `chargingStatus` / `isBatteryPresent` |

### 传感器（加速度计 / 罗盘）

`Device` 的 `sensors` 以「命令 + 事件」模型提供流式传感器读数，与 `WebSocket` 一致：契约方法
只有 `isAvailable` / `start` / `stop`（error-string ack），读数经 Lynx
`GlobalEventEmitter` 的 `sensors` 事件回传。共享层 `sensors.observe()` 按类型做
监听引用计数——第一个监听者出现时调用原生 `start`，最后一个取消时调用 `stop`，
业务不需要手动管理传感器开关：

```ts
import { sensors } from '@lynx-template/autolink-device';

if (await sensors.available('compass')) {
  const stop = sensors.observe(
    'compass',
    (reading) => {
      'background only';
      // reading.heading: 磁北方位角 0-360°
      // reading.accuracy: 估计误差角度；-1 表示不可靠
    },
    (message) => {
      // 启动失败（如 iOS 罗盘定位权限被拒）经此回调报告
    },
  );
  // stop() 取消订阅；最后一个 stop 后原生传感器自动停流
}
```

- `accelerometer` 读数为设备坐标系 m/s²，**包含重力**（静置时 z 约 9.8），三端口径一致；
- `compass` 读数为磁北方位角（0-360°，绕竖直轴），`accuracy` 是以角度计的估计误差
  （iOS 直接使用 `headingAccuracy`；Android / HarmonyOS 由精度枚举映射为
  ±15°/±30°/±45°，不可靠时 -1）；
- `timestamp` 为原生发出时刻的 epoch 毫秒，各平台原生时间源不保证跨端可比，仅用于
  排序与间隔估算。

| 平台 | `accelerometer` | `compass` | 权限 |
| --- | --- | --- | --- |
| Android | `SensorManager` `TYPE_ACCELEROMETER`（UI 速率） | `TYPE_ROTATION_VECTOR`（缺失时回落加速度计+磁力计融合），`getOrientation` 求方位角并按屏幕旋转重映射 | 均免权限 |
| iOS | `CMMotionManager` 加速度计更新（含重力） | `CLLocationManager` heading（`magneticHeading` / `headingAccuracy`） | 罗盘需定位授权：宿主声明 `NSLocationWhenInUseUsageDescription`，模块在首次 `start` 时发起申请；拒绝经 `onError` 报告，模拟器/无磁力计设备 `available()` 为 `false`。加速度计免权限 |
| HarmonyOS | `sensor.on(ACCELEROMETER)` | `sensor.on(ORIENTATION)`，`alpha` 即地磁融合方位角 | `ohos.permission.ACCELEROMETER`（system_grant，已在宿主声明）；罗盘免权限 |

与 `WebSocket` 相同，事件进入后台运行时（`'background only'`）；传感器回调高频触发，
避免在监听器里做重计算，必要时自行节流。页面销毁时三端都会停流（Android
`destroy()` 反注册、iOS `-destroy`、HarmonyOS 模块挂载的 `LynxViewClient.onDestroy()`
只移除该实例的 sensor callbacks）。

### 网络状态

`NetworkInfo` 提供按需查询与变化监听两级 API，与 `Device` 的 `sensors` 同一「命令 + 事件」模型：
第一个监听者注册原生监听并立即回推当前快照，最后一个取消时移除；能力回调可能因
信号强度变化频繁触发，三端都会按（connected, type, cellularGeneration）去重，只有
真实切换才产生事件：

```ts
import { networkInfo } from '@lynx-template/autolink-network-info';

const snapshot = await networkInfo.getInfo();
// { connected: true, type: 'wifi', cellularGeneration: null, timestamp: … }

const stop = networkInfo.observe((next) => {
  'background only';
  // next 与 getInfo 同一结构；type 为 wifi / cellular / ethernet / other / none / unknown
});
```

`cellularGeneration`（`'2g' | '3g' | '4g' | '5g' | null`）是尽力而为的附加信息：
Android 只有宿主持有 `READ_PHONE_STATE`（本模板未声明）才能上报；iOS 依赖已被系统
标记废弃（但仍在工作）的 `CTTelephonyNetworkInfo`，模拟器与无基带设备为 `null`；
HarmonyOS 无免权限的制式查询，恒为 `null`。业务文案不应依赖该字段。

| 平台 | 实现 | 权限 |
| --- | --- | --- |
| Android | `ConnectivityManager` 当前网络 + `registerDefaultNetworkCallback` | `ACCESS_NETWORK_STATE`（normal，库 manifest 声明并合并） |
| iOS | 常驻 `NWPathMonitor` + `CTTelephonyNetworkInfo` 制式映射 | 免权限 |
| HarmonyOS | `@kit.NetworkKit` `connection`：`getAllNetsSync`/`getNetCapabilitiesSync` + `createNetConnection` 事件 | `ohos.permission.GET_NETWORK_INFO`（system_grant，已在宿主声明） |

### React hooks

React 相关入口按需拆分，避免普通 Promise API 强制依赖 React：

- `@lynx-template/autolink-navigation/react#useRouteParams<T>()`：返回当前路由 init data 中类型化的 `route.params`（缺失字段为 `undefined`，使用前自行校验）；
- `@lynx-template/autolink-navigation/react#usePredictiveBackOverlay(initiallyOpen?)`：管理弹层的 `open`、`setOpen`、`present()`、`dismiss()` 与 `toggle()`；
- `@lynx-template/autolink-navigation/react#PredictiveBackOverlay`：包装 `position: fixed` 弹层，并把 Android/iOS 预测返回直接绑定到原生动画目标；
- `@lynx-template/autolink-navigation/react#useBackInterceptor(onEvent, enabled?)`：无 UI 的高级入口，适用于关闭路由或自定义生命周期；`enabled` 变化时自动注册/移除，仍遵循后进先出栈语义。
- `@lynx-template/autolink-navigation/react#useBackDismissal(onDismiss, enabled?)`：面向对话框、抽屉等「返回即关闭」的 JS 浮层——`enabled` 期间一次返回 commit 只调用 `onDismiss` 关闭浮层而不退出路由；手势取消则浮层保持打开，浮层卸载/关闭时自动归还返回权。

### 返回拦截与进度

`Back` 使用“预先声明栈顶快照”的模型。`autolink/navigation` 每次入栈或出栈都把完整的
`enabled + interceptorId + animationTargetId + revision` 同步给原生端；宿主不会在手势
开始后等待异步 JavaScript 决定是否拦截。原生端在 `start` 固定本次手势的拦截器和动画
目标，栈在过程中变化只影响下一次手势。

普通固定弹层直接使用高层组件：

```tsx
const sheet = usePredictiveBackOverlay();

<PredictiveBackOverlay
  open={sheet.open}
  onOpenChange={sheet.setOpen}
  backdropColor="rgba(0, 0, 0, 0.45)"
  motion="sheet"
>
  <view className="Sheet">...</view>
</PredictiveBackOverlay>;
```

组件自身是全屏 `position: fixed` 容器，children 是内容层，背景色由原生容器绘制。
`motion` 提供 `sheet`、`horizontal`、`none` 三个稳定预设；每帧只改变原生容器的
子层位移与背景透明度，不触发 React diff。点背景默认关闭，也可设置
`dismissOnBackdropPress={false}` 自行处理。

路由或无 UI 拦截继续使用低层栈：

```tsx
useEffect(() => {
  'background only';
  const registration = backStack.addInterceptor((event) => {
    'background only';
    if (event.phase === 'commit') {
      router.close();
    }
  });
  return registration.remove;
}, []);
```

拦截器按注册顺序组成后进先出栈。一次手势从 `start` 到 `cancel` / `commit` 固定交给
同一个栈顶拦截器；即使它在手势中途被移除，剩余事件也不会泄漏给下面的弹窗。原生
动画目标也固定为同一个 Element，不会因为这时新开弹窗而改画另一层。无 UI 拦截器的
`animationTargetId` 为空；它在栈顶时，下方可视弹层不会错误跟随返回手势。

底层 `back.setEnabled()` 与 `back.addListener()` 仍保留给需要自行管理生命周期
的场景。普通弹窗、菜单和 sheet 应统一使用 `backStack`，不要混用两套生命周期。

统一事件名为 `back`，共享封装已经完成订阅和结构校验：

```ts
interface BackEvent {
  platform: 'android' | 'ios' | 'harmony';
  phase: 'start' | 'progress' | 'cancel' | 'commit';
  progress: number;
  source: 'system' | 'gesture' | 'button';
  edge: 'left' | 'right' | 'none';
  touchX: number;
  touchY: number;
  interceptorId?: string; // 原生固定的内部栈项 ID
  gestureId?: number;     // 原生手势序号
}
```

| 平台 | 返回来源 | 事件能力 |
| --- | --- | --- |
| Android 14+ | 系统预测性返回手势 | 原生目标连续跟手；生命周期为 `start` / `cancel` / `commit`，无目标时仍发送 `progress` |
| Android 13 及更低版本 | 系统返回手势或按键 | 离散的 `start` → `commit` |
| iOS | 包内屏幕边缘手势 | 原生目标连续跟手；生命周期为 `start` / `cancel` / `commit`，无目标时仍发送 `progress`；支持左右布局方向 |
| iOS | 导航栏返回按钮 | 离散的 `start` → `commit` |
| HarmonyOS | 页面 `onBackPress()` | 离散的 `start` → `commit` |

iOS 模块从 `LynxView` responder chain 自动定位所属 VC，在页面可见且启用期间暂停
`UINavigationController` 自带侧滑，改由包内边缘手势驱动当前
`<predictive-back-overlay>`；页面消失或模块销毁时恢复系统手势和导航按钮。Android 模块
通过宿主 `FragmentActivity` 的 AndroidX `OnBackPressedDispatcher` 接收系统预测回调。
两端的逐帧路径都停留在 UI 线程，不经过 NativeModule、`GlobalEventEmitter`、后台 JS 和
React；只有 headless 拦截器为了自定义预览才继续收到 `progress`。HarmonyOS 没有公开的
返回过程 API，因此只在 `commit` 更新 React 状态，不合成假进度。

## 三端映射

| 平台 | 普通页面（`default` / `fade` / `none`） | `present` 转场 |
| --- | --- | --- |
| Android | 新建 `LynxPageActivity` | 打开前 `PixelCopy` 截当前窗口，经 `RouteSnapshotStore` 交给新 Activity；窗口背景与根布局首帧即显示截图，`onFirstScreen` 后由 `PresentBackdrop` 播放编舞 |
| iOS | `UINavigationController` push（`fade` 用 `CATransition` 包裹无动画 push） | `drawViewHierarchyInRect` 截当前页后无动画 push；`viewDidLoad` 插入截图 `UIImageView`，`lynxViewDidFirstScreen:` 后由 `PresentBackdrop` 播放编舞 |
| HarmonyOS | `Navigation` + 标准 `NavDestination`（`systemTransition`） | `window.snapshot()` 截当前窗后以 `NONE` 转场 push；`NavDestination` 首帧即渲染截图 `Image`，`LynxViewClient.onFirstScreen` 后 `animateTo` 播放编舞 |

截图必须在目标页首帧渲染前就位（Android 还需先设为窗口背景，避免主题底色闪灰），
这样无系统动画的打开对用户零感知；编舞只作用于已可见的图层。关闭路径
（`router.close()` 与系统返回键）先反向复原截图背景，再以无系统动画方式真正关页，
露出的真实上一页与截图像素对齐。Android 侧的 `enableOnBackInvokedCallback`
预测返回与该编舞不融合，present 路由通过 `OnBackPressedCallback` 走统一的反向路径。

同一 LynxView 内的菜单、Dialog 和 Sheet 不需要额外创建原生页面。Lynx 支持
`position: fixed`，`PredictiveBackOverlay` 在这个层级绘制全屏背景和面板，同时由
`autolink/navigation` 内的原生 Element 完成系统返回预览。业务只管理是否展示，不需要处理
逐帧 transform，也不会另建一套原生返回栈。
只有确实需要独立原生页面、跨 bundle 生命周期或原生窗口层级时，才使用 Navigation 的
`animation: 'present'` 打开弹层式原生页面。

NativeModules 由应用级 Autolink Registry 自动提供；Android/iOS 新路由页无需补充 Back
注册。HarmonyOS 页面只把 route registration 放入 `LynxContext.contextData`，并转发 ArkUI
离散返回事件。页面同时把 `Device` 包提供的状态栏/安全区适配器接到当前 LynxView，
继续注入 Navigation handler 与 `nativeEnvironment.safeAreaInsets`。因此
第二个 bundle 可以独立处理安全区、状态栏、返回接管和 WebSocket，也可以继续打开下一层
bundle。

## 业务 WebSocket

`WebSocket` 是 App 自己维护的正式业务模块，与 Lynx DevTool 的 HMR
WebSocket 没有依赖关系。它在 Debug 和 Release 都会注册；Release 只允许
`wss://`，Debug 额外允许 `ws://` 用于局域网调试。

```ts
import { webSocket } from '@lynx-template/autolink-websocket';

function connectRealtime() {
  'background only';
  const socket = webSocket.connect({
    url: 'wss://api.example.com/realtime',
    protocols: ['example.v1'],
    headers: { Authorization: 'Bearer token' },
  });

  socket.addEventListener('message', (event) => {
    'background only';
    if (event.dataType === 'text') {
      console.info(event.data);
    } else {
      // 二进制帧统一以标准 Base64 字符串跨越 Lynx bridge。
      console.info(`binary base64: ${event.data}`);
    }
  });

  socket.addEventListener('close', (event) => {
    'background only';
    console.info(`${event.code} ${event.reason} clean=${event.wasClean}`);
  });

  socket.opened
    .then(() => socket.send(JSON.stringify({ type: 'hello' })))
    .catch((error: Error) => console.error(error.message));

  return socket;
}
```

`webSocket.connect()` 会立即返回连接对象，`opened` 在原生握手成功后完成，
`closed` 在收到最终关闭事件后完成。一个 Lynx 页面可以同时创建多个连接；页面
销毁时宿主会取消该页面的全部连接，防止 Activity、UIViewController、ArkUI 页面或
LynxContext 被长连接持有。

| API | 说明 |
| --- | --- |
| `send(text)` | 发送文本帧；只允许在 `OPEN` 状态调用 |
| `sendBase64(value)` | 将标准 Base64 解码后发送二进制帧 |
| `close(code?, reason?)` | 请求关闭并等待原生 `close` 事件；默认 code 为 `1000` |
| `addEventListener(type, listener)` | 监听 `open`、`message`、`error`、`close`；返回取消监听函数 |

共享层校验 URL、子协议、受保护的握手 header、关闭 code，以及 123 字节的关闭
reason 限制。模块不内置自动重连、心跳或离线队列，因为这些策略依赖具体业务；上层
可以监听 `close` 后按网络状态和退避策略创建新连接。

## Lynx Autolink 集成

`autolink/` 是 monorepo 的一个 workspace 目录列表（`pnpm-workspace.yaml` 中的 `autolink/*`），
其中每个子目录都是一个独立的 Lynx 原生库 npm 包，通过 `lynx.lib.json` 清单描述平台源码：

根目录 `package.json#nativeApp.autolinkModules` 是应用实际启用的库清单。脚手架默认全选，
交互创建时可在多选 TUI 中取消可选库；只有启用库会作为根直接依赖出现在
`node_modules`，从而被 Android、iOS 与 HarmonyOS 的官方扫描器发现。未启用库仍保留
源码、原始声明与生成契约，修改清单并依次运行 `pnpm native:autolink:apply`、
`pnpm install` 即可重新启用。`navigation` 与 `device` 是三端宿主必需项；后者向宿主提供
首帧安全区和页面状态栏适配器。Android/iOS 还会强制保留 `webview-bridge`，这两个宿主
直接引用了它的适配器类型。

```text
autolink/
├── album-utils/   # AlbumUtils（相册选图 + 存图）
├── navigation/    # Navigation（应用内导航 + 系统 scheme 打开 + 系统返回拦截 + Android/iOS 预测进度）
├── biometric/     # Biometric（系统生物识别弹窗 + 锁屏凭证降级）
├── device/        # Device（设备事实、安全区、状态栏、电量、显示宽度/亮度/常亮、加速度计 + 罗盘流式读数）
├── toast/         # Toast（原生轻提示；iOS 为模块自绘气泡）
├── file-system/   # FileSystem（系统文件选择器 + URI 元数据、缓存复制、受限读取与缓存沙箱写入/删除/列举）
├── websocket/     # WebSocket（Android OkHttp / iOS NSURLSession）
├── storage/       # Storage（KV 共享 MMKV 字符串存储 + SecureStorage 小机密数据：Keystore 加密 / Keychain / HUKS）
├── clipboard/     # Clipboard（系统剪贴板纯文本）
├── haptics/       # Haptics（单击式触感反馈）
├── scanner/       # Scanner（全屏扫码 + 相册图片识码）
├── audio-player/  # AudioPlayer（本地文件音频播放 + 四种音频流）
├── network-info/  # NetworkInfo（网络类型查询 + 变化监听）
├── image-tooling/ # ImageTooling（缩放/裁剪/拼图 + EXIF/GPS 管理）
├── pressable-view/ # PressableView（原生按压反馈视图组件）
├── screenshot/    # Screenshot（LynxView 截图为 Base64）
├── share/         # Share（系统分享面板：文本 / 链接 / 本地文件）
├── webview-bridge/ # WebView 原生桥（Android/iOS；宿主直接引用其适配器）
├── permissions/   # Permissions（统一运行时权限：通知 / 相机 / 相册 / 麦克风）
├── local-notification/ # LocalNotification（本地通知：立即 / 延迟发送与取消）
└── liquid-glass/  # liquid-glass（iOS-only Element 库，见下）
```

`autolink/liquid-glass/` 是 iOS-only Element 库，自动注册 `glass-switch` 与
`glass-dropdown`；Android 与 HarmonyOS 继续使用 bundle 内的 Lynx 降级控件。

这些库注册的模块名与聚合契约完全一致，因此 JS 侧零改动。每个库同时拥有原生实现和
`types/platform-native-module.d.ts` 原始调用声明；生成的 `src/index.ts` 从包根导出该
类型及模块名常量。

`navigation` 是唯一需要宿主参与的库：`open`/`close` 的应用内导航是宿主专属逻辑
（Activity / ViewController / Navigation），模块从自身 `LynxContext` 解析出调用方
所在的宿主后委托给宿主安装的无状态 handler（Android 在 `LynxTemplateApplication`、
iOS 在 `AppDelegate` 中各调用一次 `NavigationModule.setRouteHandler(AppRouteHandler())`）；
`openURL` 则完全在库内直通系统，详见[系统路由](#系统路由)。
`biometric` 与 Navigation 的 Back 能力对 Android 宿主有相同的形态要求：`BiometricPrompt` 和
`OnBackPressedDispatcher` callback 都托管在 `FragmentActivity` 上，本模板所有创建
LynxView 的 Activity 均继承 `FragmentActivity`。iOS 使用 Face ID 还需要宿主声明
`NSFaceIDUsageDescription`。

**Android**：构建固定为 AGP 8.13.2、Gradle 8.13、compileSdk 36 与经典 Kotlin Android
插件 2.4.10，以使用 Lynx 官方 4.0.1 Autolink。`settings.gradle.kts` 应用
`org.lynxsdk.lynx.library-settings`，向上扫描 `node_modules`，把每个库的 `android/`
目录 include 成 Gradle 子项目；app 模块应用配套的 `org.lynxsdk.lynx.library-build`，
由插件接入这些项目依赖，并为每个 variant 生成
`com.lynx.tasm.library.LynxAutolinkGenerated`。生成表汇总各库经 `lynx-processor` 产生的
`LynxLibraryProviderImpl`，由 Lynx runtime 加载。宿主不再维护项目依赖循环、处理器参数或
Provider Registry。

**iOS**：`Podfile` 顶部声明 `plugin 'cocoapods-lynx-library'`（由 `Gemfile` + Bundler 管理，
先 `bundle install`），target 内调用 `use_lynx_library!`。插件扫描 `node_modules` 中的
`lynx.lib.json`，把各库以 `:path` pod 接入，并生成 `LynxLibraryRegistry` pod；宿主在构建
`LynxConfig` 时调用 `LynxGeneratedLibraryRegistry().setup(config)` 完成注册（见
`LynxPageViewController.swift` 与桥接头文件）。生成目录 `app/iosApp/generated/` 已加入
`.gitignore`。

**HarmonyOS**：宿主使用 Lynx 官方 Hvigor Autolink。每个 NativeModule 库在
`autolink/<库>/harmony/` 内携带完整源码 HAR（`oh-package.json5`、`hvigorfile.ts`、
`build-profile.json5`、`src/main/module.json5` 与 `Index.ets`），并从 `Index.ets` 导出
`LynxLibraryProviderImpl`。`lynx.lib.json#platforms.harmony.packageDir` 指向该 HAR。
根工程的 `hvigorconfig.ts` 启用官方插件；插件扫描 `node_modules` 后在
`.hvigor/lynx-autolink/entry` 生成 Registry HAR，并在 `entry/build/generated/lynx-autolink`
生成 AppStartup task。它在 Lynx runtime 创建前调用一次
`LynxLibraryRegistry.setupGlobal()`，宿主页面不再导入生成文件或逐库注册。

公开稳定版 `@lynx/lynx@4.0.1` 尚无 Registry API，因此 HarmonyOS 固定到
`4.2.0-nightly.202608180606.150.ga573c3b8`。`@lynx/lynx-library-plugin@0.1.0` 也尚未发布，
仓库暂时原样固定同一 Lynx 提交 `a573c3b8` 下的官方插件源码，位于
`app/harmonyApp/vendor/lynx-library-plugin`；正式包发布后可换成 Hvigor 依赖而无需改 HAR。
相册、文件选择器、扫码、Display 与 Screenshot 从 `LynxContext` 取得窗口、组件或
`UIAbilityContext`；Device（sensors）、WebSocket 通过 `LynxViewClient` 清理实例资源，因此 Provider
不需要页面参数。Navigation 的路由从 `LynxContext.contextData` 取得宿主导航 handler；Back 从同一
容器取得 `BackRegistration`，而模块、route session、事件载荷和同步控制器均由自身源码
HAR 导出。宿主只在 ArkUI `onBackPress` 中调用控制器，因为 HarmonyOS 没有独立订阅或
返回进度 API。Device 的页面注册对象、SafeArea 监听和 StatusBar 控制器也由自身源码
HAR 导出。

**新增一个 autolink 库**：最简单的方式是 `pnpm new:native-module <name>`，脚手架会生成
三端 stub（含官方 Provider 结构的 `harmony/` 源码 HAR）、契约、workspace 依赖与
Autolink 元数据，不生成或修改宿主 Registry。手工创建时：在 `autolink/` 下新建目录（`package.json` + `lynx.lib.json` +
`types/platform-native-module.d.ts` + `android/` + `ios/` + `harmony/`），在
`contracts/native-modules.json` 添加声明与三端实现映射，加入根 `package.json` 的
workspace 依赖后执行 `pnpm install`、`pnpm native:contracts:generate`；随后 Android
直接重新构建，Gradle 插件会扫描并生成 Registry；iOS 重新执行
`bundle exec pod install`；HarmonyOS 直接重新构建，Hvigor
插件会重新扫描并生成 Registry。
注意 Lynx 4.0.1 Gradle 插件的 Registry 生成任务不会把「新出现的库」算作输入变化：
如果构建后新模块报 `not registered by the host`，执行一次
`./gradlew :app:generateDebugLynxLibraryRegistry --rerun`（或 clean 构建）即可强制重扫。

已有模块的共享样板（`harmony/hvigorfile.ts`、`build-profile.json5`、`module.json5`，以及
ohpm `@lynx/lynx` 与 gradle `org.lynxsdk.lynx:*` 的版本钉）由 `pnpm native:modules:sync`
统一再同步，与 `pnpm new:native-module` 的脚手架输出保持同源；`pnpm check` 会先执行
`native:modules:check` 防止漂移。

## 原生实现位置

- Autolink NativeModule 库（三端）：`autolink/navigation`、`autolink/websocket`、`autolink/storage`、`autolink/clipboard`、`autolink/haptics`、`autolink/biometric`、`autolink/album-utils`、`autolink/device`、`autolink/network-info`、`autolink/image-tooling`、`autolink/file-system`、`autolink/scanner`、`autolink/screenshot`、`autolink/audio-player`、`autolink/toast`、`autolink/share`、`autolink/permissions`、`autolink/local-notification`；每个包的 HarmonyOS 实现都位于自身 `harmony/` 源码 HAR，由官方 Hvigor 插件生成 Registry HAR 与 AppStartup 自动注册；
- iOS-only Autolink Element：`autolink/liquid-glass`；
- Android 宿主：`nativemodule/` 下只保留 `AppRouteHandler.kt`（Navigation 的宿主导航）以及 `LynxPageActivity.kt`；Back 与路由导航位于 `autolink/navigation/android`，StatusBar/SafeArea/电量/传感器位于 `autolink/device/android`，Autolink Registry 只存在于 Gradle 生成目录；
- iOS 宿主：`NativeModules/AppRouteHandler.swift` 提供 Navigation 导航策略，`LynxPageViewController.swift` 创建页面；Back 与 Device 都从自身 pod 自动定位页面；
- HarmonyOS 宿主：`host/NativeRouterHost.ets` 提供 Navigation 的 ArkUI 导航策略；`pages/Index.ets` 接入 `autolink/navigation/harmony` 和 `autolink/device/harmony` 导出的薄页面适配器，不再实现宿主 NativeModule。
