# NativeModules、系统 Picker、原生路由、状态栏、返回与 WebSocket

## 设计目标

原生能力分为三层：每个 `autolink/*` 包拥有自己的原始 TypeScript 调用契约，
`lib/native-contracts` 聚合这些类型并生成模块注册表，`lib/native-bridge` 则提供所有
Lynx bundle 共享的 Promise、参数校验、返回值解码、事件生命周期和 React hooks。
Android、iOS 和 HarmonyOS 宿主分别注册同名原生模块，业务 bundle 不需要根据平台分支调用：

- `KV`：以 MMKV 保存字符串；JSON 编解码由共享 TypeScript 层完成；
- `Router`：打开另一个 bundle 对应的原生页面，或关闭当前页面；
- `StatusBar`：按页面切换状态栏图标与文字的深浅样式；
- `Back`：让当前 Lynx 页面同步声明是否接管系统返回，并接收返回生命周期事件；
- `Clipboard`：读写系统剪贴板纯文本；
- `Haptics`：单击式震动反馈，分 light / medium / heavy 三档；
- `Biometric`：静默查询生物识别（指纹 / 面容）可用性，并拉起系统认证弹窗，可选降级到锁屏凭证；
- `AlbumUtils`：从系统相册选择一张或多张图片，或把图片 URI 保存回系统相册；
- `FileSystem`：通过系统文件选择器选择一个或多个文件，查询 Picker URI 元数据、复制到应用缓存、读取 UTF-8 文本或 Base64；
- `DeviceInfo`：按需读取机型、OS 版本、App 版本/构建号、屏幕密度、locale 以及平板/折叠屏判断；
- `Battery`：按需读取电量（0..1，读不到时为 null）与充电状态；
- `Toast`：一次性原生轻提示（info / success / error），替代 bundle 内自绘的 `<ToastHost />` 组件；
- `Display`：按需查询屏幕宽度、当前窗口宽度与当前 LynxView 宽度（统一为 Lynx 逻辑像素），以及窗口亮度读取/设置与屏幕常亮；
- `Sensors`：加速度计与罗盘（磁北方位角）流式读数，经 `GlobalEventEmitter` 事件回传，监听计数归零自动停流；
- `WebSocket`：提供不依赖 DevTool 的长连接、文本/二进制收发和生命周期事件；
- `Screenshot`：把整个 LynxView、某个元素或当前原生页面截为 PNG/JPEG 写入应用缓存目录；
- `Scanner`：拉起全屏扫码页识别 QR / 条形码，并支持对相册图片本地识码；
- `SecureStorage`：小型机密数据（token、会话密钥等）的 get / set / remove，Android 用 Keystore AES-GCM 加密、iOS 用 Keychain、HarmonyOS 用 HUKS；
- `main` + `predictive-back-sheet` bundle：包含可叠加三层透明原生页面的预测性返回演示。

其中 `WebSocket`、`KV`、`Clipboard`、`Haptics`、
`AlbumUtils`、`FileSystem`、`Biometric`、`DeviceInfo`、`Battery`、`Display`、`Sensors`、`Screenshot`、`Scanner` 与 `SecureStorage` 在 Android 和 iOS 上由
`autolink/` workspace 目录中的 Lynx 原生库提供并自动注册（见下文「Lynx Autolink 集成」）；
HarmonyOS 不支持 Autolink，仍由宿主手动注册同名模块。其余模块三端均保持宿主手动注册。

三个平台都使用 MMKV ID `lynx.native.kv`。同一 App 内的所有 bundle 共享这个实例，但不同平台、不同设备之间不会自动同步数据。

### 契约来源与分层

每个 Autolink NativeModule 的原始调用签名定义在所属包的
`types/platform-native-module.d.ts`，例如 `KV` 位于
`autolink/mmkv/types/platform-native-module.d.ts`。声明类本身就是 JS 侧的原始类型，
不再在聚合包里复制一遍方法签名。宿主专属、不能由 Autolink 提供的 `Back` 和
`StatusBar` 原始接口保留在 `lib/native-contracts/src/host.ts`。

`contracts/native-modules.json` 只保存模块名、声明位置、Autolink 包和三端实现位置的
映射元数据。`pnpm native:contracts:generate` 读取上述 TypeScript 声明，生成
`@lynx-app/native-contracts` 的模块名、方法白名单、参数个数和类型注册表，同时让各
Autolink 包从根入口导出自己的原始类型与模块名常量。`lib/native-bridge` 和 WebView
bridge 都消费该聚合结果，不再各自声明 `AppModules` 或硬编码模块、方法字符串。

`native-bridge` 仍然保留，因为生成类只描述 callback 形式的传输协议，不包含 Promise
封装、运行时参数校验、JSON/事件解码、LIFO 返回栈或 React hooks。业务 bundle 应使用
`@lynx-app/native-bridge`；只有桥接基础设施需要直接消费原始契约。

`pnpm native:contracts:check` 除了检查生成物，还会核对
`package.json#nativeApp.platforms` 中启用平台的原生实现：Android 的
`@LynxMethod`、iOS 的 `methodLookup`、HarmonyOS 的模块方法都必须与声明中的
名称和参数个数一致。修改已有模块时更新所属包的声明和三端实现；新增模块用
`pnpm new:native-module <name>` 一步生成三端 stub、包骨架、契约元数据和宿主注册
（生成的 `ping` 示例方法可直接通过检查），再替换为真实实现。该检查已接入 `pnpm check`。

### 命名迁移

本次统一移除了模块名中的 `Native` 前缀和 `Module` 后缀，并将 bridge 包名改为
`@lynx-app/native-bridge`。这是一次破坏性变更，不保留旧名称的兼容别名：

| 旧 NativeModules 名 / JS facade | 新 NativeModules 名 / JS facade |
| --- | --- |
| `NativeKVModule` / `nativeKV` | `KV` / `kv` |
| `NativeRouterModule` / `nativeRouter` | `Router` / `router` |
| `NativeStatusBarModule` / `nativeStatusBar` | `StatusBar` / `statusBar` |
| `NativeBackModule` / `nativeBack` / `nativeBackStack` | `Back` / `back` / `backStack` |
| `NativeClipboardModule` / `nativeClipboard` | `Clipboard` / `clipboard` |
| `NativeHapticsModule` / `nativeHaptics` | `Haptics` / `haptics` |
| `NativeImagePickerModule` / `nativeImagePicker` | `AlbumUtils` / `albumUtils`（原 `ImagePicker` / `imagePicker`，并新增存图能力） |
| `NativeFilePickerModule` / `nativeFilePicker` | `FileSystem` / `fileSystem`（`pick` 方法，与文件操作合并） |
| 新增 | `FileSystem` / `fileSystem` |
| `NativeWebSocketModule` / `nativeWebSocket` | `WebSocket` / `webSocket` |

返回事件也由 `nativeBack` 改为 `back`，`useNativeBackInterceptor` 改为
`useBackInterceptor`；bridge 导出的模块相关类型遵循同一规则，例如
`NativeRouteOptions` 改为 `RouteOptions`。

## JavaScript API

业务代码只依赖 workspace 包，不直接访问全局 `NativeModules`：

```tsx
import {
  albumUtils,
  backStack,
  battery,
  fileSystem,
  kv,
  router,
  statusBar,
} from '@lynx-app/native-bridge';

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
    presentation: 'push',
    statusBarStyle: 'dark-content',
    params: { userID: '42' },
  });
}

async function useDarkPageChrome() {
  'background only';
  await statusBar.setStyle('light-content');
}

async function openSheet() {
  'background only';
  await router.open({
    bundle: 'native-capabilities',
    presentation: 'sheet',
    transparent: true,
    params: { mode: 'sheet', source: 'main' },
  });
}

async function openExternalPage() {
  'background only';
  // The system resolves the scheme: any installed app that registered it can
  // handle the URL, including this app's own `lynxapp://` pages.
  await router.openURL('weixin://');
  await router.openURL('lynxapp://main');
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

### KV 能力

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

### SecureStorage 能力

| 方法 | 说明 |
| --- | --- |
| `setString(key, value)` | 加密保存一个小型机密字符串 |
| `getString(key, defaultValue?)` | 读取并解密；缺失（或校验失败，见下文）时返回默认值或 `null` |
| `remove(key)` | 删除一个键（键不存在同样视为成功） |

`SecureStorage` 面向 token、会话凭证等小型机密数据，value 上限 65536 字符；三端实现：

- **Android**（`autolink/secure-storage`）：AES-256-GCM 密钥保存在 AndroidKeyStore 中且不可导出，落盘的只有随机 IV 与密文（应用私有 `SharedPreferences`）；
- **iOS**（`autolink/secure-storage`）：Keychain 通用密码条目（`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`，不随备份迁移到其他设备）；
- **HarmonyOS**（宿主 `native/SecureStorageModule.ets`）：AES-256-GCM 密钥保存在 HUKS 中，密文存放在专用 MMKV 实例 `lynx.secure.storage`。

与 `KV` 不同，数据不跨平台、不跨设备同步。密文被篡改或系统密钥被清除时，
GCM 校验失败，`getString` 按缺失处理并返回默认值；`remove` 与 KV 一致（幂等）。
存放结构化机密时仍由调用方自行 JSON 编解码。

### 路由参数

```ts
interface RouteOptions {
  bundle: string;
  presentation?: 'push' | 'sheet';
  transparent?: boolean;
  statusBarStyle?: 'dark-content' | 'light-content';
  animation?: 'default' | 'fade' | 'none';
  params?: Record<string, unknown>;
}
```

`presentation` 只区分普通页面（`push`）和透明弹层（`sheet`，自动带上
`transparent: true`）。打开与关闭的原生过渡动画由 `animation` 控制：
`default` 保持各平台标准推入过渡，`fade` 双向淡入淡出，`none`
打开与关闭都瞬时完成。非法取值会被共享 TypeScript 层和三端原生模块分别拒绝。

`bundle` 必须匹配 `^[a-z0-9][a-z0-9-]*$`，并与 workspace `package.json` 的 `lynxBundle.name` 一致。路由页通过 init data 收到统一结构：

```json
{
  "route": {
    "bundle": "native-capabilities",
    "presentation": "sheet",
    "transparent": true,
    "statusBarStyle": "dark-content",
    "animation": "default",
    "params": {
      "source": "main"
    }
  }
}
```

页面调用 `router.close()` 返回上一层；根页面不会被关闭，并会返回错误。

### 系统路由

`router.openURL(url)` 把 URL 交给操作系统解析：注册了该 scheme 的任意 App
都可以响应（`weixin://`、`imeituan://`、`alipay://xxx`、`https://…`），
当前 App 自己注册的 scheme 也会命中（本模板注册了 `lynxapp://main`，
`bundle/main` 的 "System URL" 卡片演示了这一用法）。没有 App 能处理时
Promise 会以宿主错误消息 reject。共享层要求 URL 非空、声明 scheme 且
不含首尾空白，并拒绝 `javascript:` 与 `data:`。

三端实现：Android 用 `ACTION_VIEW` 隐式 Intent（直接 `startActivity` 不受
Android 11+ 包可见性限制，无需 `<queries>`；只有 `resolveActivity` 之类的
查询才需要）；iOS 用 `UIApplication.open`（它不需要
`LSApplicationQueriesSchemes`，只有 `canOpenURL` 检查才需要）；HarmonyOS
用 `UIAbilityContext.openLink`。要在系统里注册自己的 scheme：Android 在
`AndroidManifest.xml` 里给目标 Activity 加 `VIEW`/`BROWSABLE` intent-filter，
iOS 在 `Info.plist` 声明 `CFBundleURLTypes`，HarmonyOS 在 `module.json5`
的 ability `skills` 里声明 `uris.scheme`。

### 状态栏样式

`statusBarStyle` 和 `statusBar.setStyle()` 描述的是状态栏前景，而不是页面背景：

- `dark-content`：深色图标和文字，适用于白色或其他浅色背景；
- `light-content`：白色图标和文字，适用于深色背景。

路由参数决定目标原生页面创建时的初始样式，默认是 `dark-content`；bridge 用于页面加载后动态切换当前页面。三个宿主都保持状态栏背景透明，让 Lynx 页面继续绘制到系统栏下面。路由 init data 中也包含 `route.statusBarStyle`，业务可以读取并保持自己的视觉状态一致。

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

### 生物识别

`Biometric` 分为静默查询和交互认证两级 API：

```ts
import { biometric } from '@lynx-app/native-bridge';

// 静默查询：不弹任何 UI，用于决定是否展示"开启生物识别"入口。
const support = await biometric.checkSupport();
// { canAuthenticate, reason, biometryType, deviceCredentialSetup }

// 拉起系统认证弹窗，resolve 出结构化结果。
const outcome = await biometric.authenticate({
  title: 'Lynx Template',            // Android / HarmonyOS 弹窗标题；iOS 无标题
  reason: 'Confirm your identity.',  // iOS localizedReason / Android 描述
  cancelButtonTitle: 'Use password',  // Android 负按钮 / iOS 降级按钮文案
  allowDeviceCredential: false,      // 是否允许锁屏凭证兜底，默认 false
});
if (outcome.success) {
  // 通过
} else if (outcome.code === 'userFallback') {
  // 用户点了降级按钮，跳转业务自己的密码界面
}
```

`authenticate` 永远 resolve 一个结构化 outcome，不因取消而 reject：用户取消
（`userCancel`）、点击降级按钮（`userFallback`）、系统打断（`systemCancel`）都是正常
业务分支，只有参数非法或宿主未注册模块才 reject / throw。`success` 恒等于
`code === 'success'`。同一页面同时只允许一个活动请求，第二个请求 resolve 为
`busy`。`reason` / `title` 为空会被共享层与三端原生分别拒绝。

`checkSupport` 返回的 `reason` 说明当前为什么不能认证：`ok`、`noHardware`（无传感器
或不可用）、`notEnrolled`（未录入）、`locked`（多次失败被锁定）、`noDeviceCredential`
（未设置锁屏凭证）等。`biometryType` 在 iOS 和 HarmonyOS 上报告 `face` /
`fingerprint`，Android 的 androidx.biometric 不暴露传感器类型，报告 `unknown`，
业务文案应准备兜底说法。

`allowDeviceCredential: false`（默认）是纯生物识别模式，用户点降级按钮会得到显式的
`userFallback`，由业务决定跳转自己的密码界面；`true` 则交给系统凭证 UI 自动兜底
（iOS `.deviceOwnerAuthentication`、Android `DEVICE_CREDENTIAL | BIOMETRIC_WEAK`、
HarmonyOS authType 追加 `PIN`），此时不会再出现 `userFallback`。

三端实现与权限边界：

| 平台 | 能力查询 | 认证 | 权限 / 前置条件 |
| --- | --- | --- | --- |
| Android | `BiometricManager.canAuthenticate(BIOMETRIC_WEAK)` | `androidx.biometric.BiometricPrompt` | `USE_BIOMETRIC`（normal，库 manifest 声明并合并）；宿主 Activity 须为 `FragmentActivity` |
| iOS | `LAContext.canEvaluatePolicy` + `biometryType` | `evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics / .deviceOwnerAuthentication)` | Touch ID 无需声明；Face ID 需宿主 `NSFaceIDUsageDescription`（已在宿主声明） |
| HarmonyOS | `userAuth.getAvailableStatus`（按指纹 / 面容 / PIN 分别探测） | `userAuth.getUserAuthInstance(...).start()`，ATL2 | `ohos.permission.ACCESS_BIOMETRIC`（normal 级 system_grant，已在 module.json5 声明） |

Android 宿主的 `MainActivity` 与 `LynxPageActivity` 因此继承
`FragmentActivity`（app 依赖 `androidx.fragment`），模块从 `LynxContext` 解包出
当前 Activity 后托管系统弹窗。HarmonyOS 的错误码（`UserAuthResultCode`）映射进统一
outcome：`FAIL` → `failed`（指纹 / 面容识别未通过，Android / iOS 的单次不匹配由系统
弹窗内部重试，不会产生该码）、`CANCELED` → `userCancel`、`LOCKED` → `locked`、
`NOT_ENROLLED` → `notEnrolled` 等。

**安全边界**：`authenticate` 只做"本机在场验证"（presence），`success` 表示用户当次
通过了系统生物识别，但客户端布尔值总可以被 hook，**不能单独作为服务端敏感操作的凭据**。
需要服务端可信时使用下面两个签名 API。

### 生物识别挑战签名（服务端可校验）

`Biometric` 维护一把硬件绑定的 EC P-256 签名密钥，私钥永不出安全硬件，且只能在一次
成功的生物识别弹窗内使用。协议分两步：

```ts
import { biometric } from '@lynx-app/native-bridge';

// 1) 每设备一次：生成密钥，把公钥交给服务端绑定到账号。
const created = await biometric.createSigningKey();
if (created.success) {
  await api.post('/account/biometric-key', { publicKey: created.publicKey });
}

// 2) 每次敏感操作：服务端下发一次性 nonce，客户端弹生物识别并对 nonce 签名。
const { challenge } = await api.post('/auth/challenge');
const signed = await biometric.signChallenge({
  challenge,                       // 服务端 nonce 的 Base64
  title: '确认支付',
  reason: '使用生物识别签名确认本次支付。',
});
if (signed.success) {
  await api.post('/auth/verify', { challenge, signature: signed.signature });
}
```

密钥与签名格式三端统一：

- **公钥**：65 字节非压缩 EC 点（`0x04 || X || Y`）的 Base64；
- **签名**：对 challenge 原始字节的 SHA256 ECDSA 签名，统一为 64 字节 `r || s`
  （IEEE P1363）的 Base64（Android / HarmonyOS 原生输出为 ASN.1 DER，模块内已转换）。

| 平台 | 私钥存放 | 生物绑定 |
| --- | --- | --- |
| Android | AndroidKeyStore（`setUserAuthenticationRequired(true)`，重录生物识别即失效） | `BiometricPrompt.CryptoObject`，要求 `BIOMETRIC_STRONG`（Class 3） |
| iOS | 优先 Secure Enclave；模拟器等无 SE 场景回退为 keychain 软件密钥 | `kSecAttrAccessControl` = `biometryCurrentSet | privateKeyUsage`，`evaluatePolicy` 后用同一 `LAContext` 取 key 签名 |
| HarmonyOS | HUKS（`HUKS_TAG_USER_AUTH_TYPE` = 指纹 \| 面容） | `initSession` 产生 challenge → `getUserAuthInstance` 用同一 challenge 认证拿 authToken → `finishSession` 携带 `HUKS_TAG_AUTH_TOKEN` 完成 |

签名 API 复用 `authenticate` 的 outcome 语义（取消 / 降级 / 锁定等 resolve 结构化
code），并新增两个 code：`notSupported`（硬件不支持，如 Android 无 Class 3 传感器）与
`keyNotFound`（本设备没有密钥，或用户重录生物识别导致密钥失效——后者是刻意的安全
行为，处理方式是重新 `createSigningKey` 并让服务端重新绑定公钥）。签名 API 不支持
`allowDeviceCredential`，始终要求生物识别。

服务端验证示例（Node.js，验签 P1363 签名 + 重建 SPKI）：

```ts
import { createPublicKey, verify } from 'node:crypto';

const SPKI_PREFIX = Buffer.from(
  '3059301306072a8648ce3d020106082a8648ce3d030107034200', 'hex',
);

function verifyBiometricSignature(
  publicKeyBase64: string,   // createSigningKey 返回的 65 字节点
  challengeBase64: string,  // 下发给客户端的同一 nonce
  signatureBase64: string,  // signChallenge 返回的 64 字节 r||s
): boolean {
  const spki = Buffer.concat([SPKI_PREFIX, Buffer.from(publicKeyBase64, 'base64')]);
  const key = createPublicKey({ key: spki, format: 'der', type: 'spki' });
  return verify(
    'sha256',
    Buffer.from(challengeBase64, 'base64'),
    { key, dsaEncoding: 'ieee-p1363' },
    Buffer.from(signatureBase64, 'base64'),
  );
}
```

nonce 必须一次性且短时效（如 60 秒），否则签名可被重放。这套机制防的是"客户端结果被
hook / 伪造"：攻击者可以随意触发签名调用，但无法导出私钥，签名在安全硬件内要求一次
真实的生物识别事件；它不防"用户被诱导对可疑操作刷脸"，操作内容应写进 `title` /
`reason` 并由服务端在签名 payload 中绑定业务参数。`bundle/main` 的 "Make key" /
"Sign" 按钮用本地随机 nonce 演示完整流程（实际业务中 nonce 应来自服务端）。


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
支持时取得持久读授权；iOS 会把结果复制到 `Library/Caches/LynxPicker` 后返回 `file://` URI；
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

| 方法 | 返回值 | 说明 |
| --- | --- | --- |
| `fileSystem.pick(options?)` | `Promise<string[]>` | 打开系统文件选择器；取消时解析为空数组 |
| `fileSystem.stat(uri)` | `Promise<FileInfo>` | 获取名称、MIME 和字节数；内容提供方无法确定时相应字段为 `null` |
| `fileSystem.copyToCache(uri)` | `Promise<string>` | 流式复制到应用缓存，返回 `file://` URI；缓存仍可能被系统清理 |
| `fileSystem.readText(uri, options?)` | `Promise<string>` | 严格按 UTF-8 解码；默认上限 1 MiB |
| `fileSystem.readBase64(uri, options?)` | `Promise<string>` | 返回标准 Base64；默认源文件上限 5 MiB |
| `fileSystem.readArrayBuffer(uri, options?)` | `Promise<ArrayBuffer>` | 在 JS 侧解码 Base64 得到 ArrayBuffer；默认源文件上限 5 MiB |

`maxBytes` 必须是 `1..20 MiB` 的整数，限制的是编码前源文件大小。Base64 会额外膨胀约三分之一，
`readArrayBuffer` 复用同一条 Base64 通道再在 JS 侧解码，因此开销与 `readBase64` 相同；
大文件上传不应经过 JS/Base64 bridge，应由网络层直接流式读取 URI。Android 支持 Picker 的
`content://` 和缓存 `file://` URI；iOS Picker 已先复制到缓存，因此 `FileSystem` 接受 `file://`；
HarmonyOS 直接使用 Picker URI。该模块沿用 Picker 授予的访问范围，不新增媒体或存储权限。

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
import { scanner } from '@lynx-app/native-bridge';

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

### 截图

`Screenshot` 把视图快照编码为 PNG/JPEG 写入应用缓存目录（`<cache>/LynxImages/`），
返回 `file://` URI 与像素尺寸；产物可以直接交给 `AlbumUtils.saveToAlbum` 存回相册：

```ts
import { albumUtils, screenshot } from '@lynx-app/native-bridge';

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

`capture` 在 Android 与 iOS 上支持通过 `idSelector` 截取页内某个元素——Lynx 元素
设置 `idSelector` 属性后即可被原生查找。HarmonyOS 的 LynxContext 既不暴露视图、
也没有元素查找 API，因此只能截取宿主 LynxView 容器，传入 `idSelector` 会被
reject 而不是静默忽略。

`capturePage` 截取的是「当前原生页面」的合成像素，等价于 Android 的窗口
PixelCopy：包含 LynxView 之外的原生内容（原生标题栏、叠加层等），且不需要任何
截屏权限。

| 行为 | Android | iOS | HarmonyOS |
| --- | --- | --- | --- |
| `capture` 默认 | `LynxView.draw(Canvas)` 到 Bitmap | `drawViewHierarchyInRect`，未上屏时回退 `layer.renderInContext` | `componentSnapshot.get()` 截宿主容器 |
| `capture` + `idSelector` | `LynxView.findViewByIdSelector()` | `LynxView viewWithIdSelector:` | 不支持，reject |
| `capturePage` | `PixelCopy.request(window, …)`；API 24/25 回退到绘制 decor view | key window 快照 | `componentSnapshot.get()` 截页面根容器 |

JPEG 输出先合成白色底（JPEG 没有透明通道）；视图绘制在主线程执行，编码与文件
IO 在后台线程完成。目标未布局（宽高为 0）、`idSelector` 无匹配或 LynxView 尚未
attach 时 reject。

### 设备信息、显示宽度与亮度

`DeviceInfo` 一次性返回设备与应用事实，`Display` 按需提供三种宽度与亮度/常亮控制；两者都是
调用时现查，旋转、折叠/展开、多窗口拖拽与配置变更后立即反映最新值：

```ts
import { deviceInfo, display } from '@lynx-app/native-bridge';

const info = await deviceInfo.getInfo();
// { model, manufacturer, osVersion, osApiLevel, appVersion, appBuild,
//   density, locale, isTablet, isFoldable }

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
import { toast } from '@lynx-app/native-bridge';

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

### 电量

`Battery` 按需读取当前电量与充电状态，三端均免权限：

```ts
import { battery } from '@lynx-app/native-bridge';

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

`Sensors` 以「命令 + 事件」模型提供流式传感器读数，与 `WebSocket` 一致：契约方法
只有 `isAvailable` / `start` / `stop`（error-string ack），读数经 Lynx
`GlobalEventEmitter` 的 `sensors` 事件回传。共享层 `sensors.observe()` 按类型做
监听引用计数——第一个监听者出现时调用原生 `start`，最后一个取消时调用 `stop`，
业务不需要手动管理传感器开关：

```ts
import { sensors } from '@lynx-app/native-bridge';

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
避免在监听器里做重计算，必要时自行节流。页面销毁时三端宿主都会停流（Android
`destroy()` 反注册、iOS `-destroy`、HarmonyOS 页面 `aboutToDisappear` 销毁
controller）。

### 共享 hooks

`@lynx-app/native-bridge` 还提供两个与原生能力配套的 React hooks：

- `useRouteParams<T>()`：返回当前路由 init data 中类型化的 `route.params`（缺失的字段为 `undefined`，使用前自行校验）；
- `useBackInterceptor(onEvent, enabled?)`：声明式注册返回拦截器，`enabled` 变化时自动注册/移除，且始终调用最新的 `onEvent`；拦截器仍遵循后进先出栈语义。

### 返回拦截与进度

`Back` 使用“预先启用 + 事件通知”的模型。共享层的
`backStack.addInterceptor()` 会在第一个拦截器入栈时启用原生返回，在最后一个
拦截器出栈时关闭。宿主不会在手势开始后等待异步 JavaScript 决定是否拦截。启用后，
栈顶业务必须处理 `commit`（关闭弹窗或调用 `router.close()`），否则原生返回会被
消费而界面保持不动。

```tsx
useEffect(() => {
  'background only';
  const registration = backStack.addInterceptor((event) => {
    'background only';
    if (event.phase === 'progress') {
      // event.progress 为 0..1，可驱动 Lynx 自己的返回预览。
    }
    if (event.phase === 'commit') {
      router.close();
    }
  });
  return registration.remove;
}, []);
```

拦截器按注册顺序组成后进先出栈。一次手势从 `start` 到 `cancel` / `commit` 固定交给
同一个栈顶拦截器；即使它在手势中途被移除，剩余事件也不会泄漏给下面的弹窗。关闭
顶层弹窗只会移除自己的注册项，下层弹窗自动成为新的栈顶，原生返回保持启用。

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
}
```

| 平台 | 返回来源 | 事件能力 |
| --- | --- | --- |
| Android 14+ | 系统预测性返回手势 | `start` / 连续 `progress` / `cancel` / `commit` |
| Android 13 及更低版本 | 系统返回手势或按键 | 离散的 `start` → `commit` |
| iOS | 宿主接管的屏幕边缘手势 | `start` / 连续 `progress` / `cancel` / `commit`；支持左右布局方向 |
| iOS | 导航栏返回按钮 | 离散的 `start` → `commit` |
| HarmonyOS | 页面 `onBackPress()` | 离散的 `start` → `commit` |

iOS 在启用期间会暂停 `UINavigationController` 自带的侧滑返回，改由宿主边缘手势上报进度；`commit` 后仍由 Lynx 业务决定关闭页面。因此这里提供的是统一可观测进度，不是 UIKit 原生交互式转场对象。Android 注册默认优先级回调后同样由当前 Lynx 页面拥有返回，系统不会替业务自动完成页面动画。

`progress` 通过 Lynx `GlobalEventEmitter` 进入后台运行时，适合更新返回预览状态；如果业务要求逐帧、与原生转场严格同步的动画，应进一步实现原生 UI 或渲染线程专用通道。

## 三端映射

| 平台 | 普通页面 | 透明页面 / `sheet` |
| --- | --- | --- |
| Android | 新建 `LynxPageActivity` | 新建 Manifest 中预先声明透明主题的 `TransparentLynxPageActivity` |
| iOS | 有 `UINavigationController` 时 push，否则 full-screen present | `.overFullScreen` present，LynxView 和宿主 view 均透明 |
| HarmonyOS | `Navigation` + 标准 `NavDestination` | `NavDestinationMode.DIALOG` + 透明背景 |

Android 的 `windowIsTranslucent` 必须在 Activity 窗口创建前由 Manifest 主题确定，不能只在 `onCreate()` 中调用 `setTheme()`；否则透明 LynxView 后面会显示黑色窗口背景。

仓库中的 `Open stack demo` 会打开 `predictive-back-sheet`。每次 `Push Activity` 都通过 `presentation: 'sheet'` 新建一个透明原生页面，因此三层弹窗对应三层真实 Activity / ViewController / NavDestination，而不是在根 bundle 内绘制三层 overlay。每层只注册自己的返回拦截器；预测手势进度驱动当前全宽 sheet 向下位移，`commit` 退场完成后调用 `router.close()`，从而露出下面一层原生页面。

这套行为已经封装在 `@lynx-template/activity-sheet`：`openActivityBottomSheet()` 负责以透明 sheet 路由打开目标 bundle，`useActivityBottomSheet()` 负责返回生命周期和关闭时序，`ActivityBottomSheet` 负责遮罩、全宽面板、grabber、动画与底部安全区。业务 bundle 只需要传入自己的内容；完整示例见 `lib/activity-sheet/README.md`。

每个新路由页都会重新注册全部 NativeModules，并继续注入 `nativeEnvironment.safeAreaInsets`。因此第二个 bundle 可以独立处理安全区、状态栏、返回接管和 WebSocket，也可以继续打开下一层 bundle。

## 业务 WebSocket

`WebSocket` 是 App 自己维护的正式业务模块，与 Lynx DevTool 的 HMR
WebSocket 没有依赖关系。它在 Debug 和 Release 都会注册；Release 只允许
`wss://`，Debug 额外允许 `ws://` 用于局域网调试。

```ts
import { webSocket } from '@lynx-app/native-bridge';

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

```text
autolink/
├── album-utils/   # AlbumUtils（相册选图 + 存图）
├── battery/       # Battery（电量 + 充电状态）
├── biometric/     # Biometric（系统生物识别弹窗 + 锁屏凭证降级）
├── device-info/   # DeviceInfo（机型、OS/App 版本、密度、locale、平板/折叠屏）
├── display/       # Display（屏幕宽 / 窗口宽 / LynxView 宽 / 亮度 / 常亮）
├── sensors/       # Sensors（加速度计 + 罗盘流式读数）
├── toast/         # Toast（原生轻提示；iOS 为模块自绘气泡）
├── file-system/   # FileSystem（系统文件选择器 + URI 元数据、缓存复制与受限读取）
├── websocket/     # WebSocket（Android OkHttp / iOS NSURLSession）
├── mmkv/          # KV（MMKV 字符串存储）
├── secure-storage/ # SecureStorage（小机密数据：Keystore 加密 / Keychain）
├── clipboard/     # Clipboard（系统剪贴板纯文本）
├── haptics/       # Haptics（单击式触感反馈）
├── scanner/       # Scanner（全屏扫码 + 相册图片识码）
└── router/        # Router（应用内导航 + 系统 scheme 打开）
```

`autolink/liquid-glass/` 是 iOS-only Element 库，自动注册 `glass-switch` 与
`glass-dropdown`；Android 与 HarmonyOS 继续使用 bundle 内的 Lynx 降级控件。

这些库注册的模块名与聚合契约完全一致，因此 JS 侧零改动。每个库同时拥有原生实现和
`types/platform-native-module.d.ts` 原始调用声明；生成的 `src/index.ts` 从包根导出该
类型及模块名常量。

`router` 是唯一需要宿主参与的库：`open`/`close` 的应用内导航是宿主专属逻辑
（Activity / ViewController / Navigation），模块从自身 `LynxContext` 解析出调用方
所在的宿主后委托给宿主安装的无状态 handler（Android 在 `LynxTemplateApplication`、
iOS 在 `AppDelegate` 中各调用一次 `RouterModule.setRouteHandler(AppRouteHandler())`）；
`openURL` 则完全在库内直通系统，详见[系统路由](#系统路由)。
`biometric` 是唯一对宿主有形态要求的库：Android 的 `BiometricPrompt` 必须托管在
`FragmentActivity` 上，本模板的两个宿主 Activity 已改为继承 `FragmentActivity`；
iOS 使用 Face ID 需要宿主声明 `NSFaceIDUsageDescription`。

**Android**：`settings.gradle.kts` 应用 `org.lynxsdk.lynx.library-settings` 插件（Maven Central），
它会向上扫描 `node_modules`，把每个库的 `android/` 目录 include 成 Gradle 子项目；app 模块按
`lynx_library__*` 项目名前缀动态依赖这些子项目。官方的 `library-build` 插件目前仍使用 AGP 9
已移除的旧 Variant API，无法在本模板的 AGP 9.3.1 上应用，因此 app 侧注册胶水由手写的
`LynxAutolinkRegistry.java` 承担：它把各库由 `lynx-processor` 注解处理器生成的
`LynxLibraryProviderImpl` 交给 `com.lynx.tasm.library.LynxLibraryRegistry.setup(builder)`。
Lynx 发布兼容 AGP 9 的插件后，可删除该类并换回官方生成物。

**iOS**：`Podfile` 顶部声明 `plugin 'cocoapods-lynx-library'`（由 `Gemfile` + Bundler 管理，
先 `bundle install`），target 内调用 `use_lynx_library!`。插件扫描 `node_modules` 中的
`lynx.lib.json`，把各库以 `:path` pod 接入，并生成 `LynxLibraryRegistry` pod；宿主在构建
`LynxConfig` 时调用 `LynxGeneratedLibraryRegistry().setup(config)` 完成注册（见
`LynxPageViewController.swift` 与桥接头文件）。生成目录 `app/iosApp/generated/` 已加入
`.gitignore`。

**HarmonyOS**：Lynx Autolink 尚未覆盖 HarmonyOS，宿主继续在
`app/harmonyApp/entry/src/main/ets/native/` 手动注册同名模块，JS 契约不变。

**新增一个 autolink 库**：在 `autolink/` 下新建目录（`package.json` + `lynx.lib.json` +
`types/platform-native-module.d.ts` + `android/` + `ios/`），在
`contracts/native-modules.json` 添加声明与三端实现映射，加入根 `package.json` 和
`lib/native-contracts/package.json` 的 workspace 依赖后执行 `pnpm install` 与
`pnpm native:contracts:generate`；Android 侧在 `LynxAutolinkRegistry.PROVIDERS` 中加一条
provider 类名，iOS 侧重新 `bundle exec pod install` 即可。

## 原生实现位置

- Autolink 库（Android + iOS）：`autolink/websocket`、`autolink/mmkv`、`autolink/secure-storage`、`autolink/clipboard`、`autolink/haptics`、`autolink/biometric`、`autolink/album-utils`、`autolink/device-info`、`autolink/battery`、`autolink/display`、`autolink/sensors`、`autolink/file-system`、`autolink/router`、`autolink/scanner`、`autolink/screenshot`、`autolink/toast`；
- iOS-only Autolink Element：`autolink/liquid-glass`；
- Android 宿主：`nativemodule/` 下的 `AppRouteHandler.kt`（Router 的宿主导航）、`StatusBarModule.kt`、`BackModule.kt`，以及 `LynxPageActivity.kt`、`LynxAutolinkRegistry.java`；
- iOS 宿主：`NativeModules/` 下的 `AppRouteHandler.swift`（Router 的宿主导航）与其他宿主模块、`LynxPageViewController.swift`；
- HarmonyOS 宿主：`native/` 下的各模块、`pages/Index.ets`。
