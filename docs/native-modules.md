# NativeModules、原生路由、状态栏、返回与 WebSocket

## 设计目标

`lib/native-bridge` 是所有 Lynx bundle 共享的 TypeScript 契约与调用封装。Android、iOS 和 HarmonyOS 宿主分别注册同名原生模块，业务 bundle 不需要根据平台分支调用：

- `NativeKVModule`：以 MMKV 保存字符串；JSON 编解码由共享 TypeScript 层完成；
- `NativeRouterModule`：打开另一个 bundle 对应的原生页面，或关闭当前页面；
- `NativeStatusBarModule`：按页面切换状态栏图标与文字的深浅样式；
- `NativeBackModule`：让当前 Lynx 页面同步声明是否接管系统返回，并接收返回生命周期事件；
- `NativeWebSocketModule`：提供不依赖 DevTool 的长连接、文本/二进制收发和生命周期事件；
- `main` + `predictive-back-sheet` bundle：包含可叠加三层透明原生页面的预测性返回演示。

三个平台都使用 MMKV ID `lynx.native.kv`。同一 App 内的所有 bundle 共享这个实例，但不同平台、不同设备之间不会自动同步数据。

## JavaScript API

业务代码只依赖 workspace 包，不直接访问全局 `NativeModules`：

```tsx
import {
  nativeBackStack,
  nativeKV,
  nativeRouter,
  nativeStatusBar,
} from '@lynx-template/native-bridge';

async function saveSession() {
  'background only';
  await nativeKV.setJSON('session', { token: 'example' });
  const session = await nativeKV.getJSON('session', { token: '' });
  return session.token;
}

async function openProfile() {
  'background only';
  await nativeRouter.open({
    bundle: 'profile',
    presentation: 'push',
    statusBarStyle: 'dark-content',
    params: { userID: '42' },
  });
}

async function useDarkPageChrome() {
  'background only';
  await nativeStatusBar.setStyle('light-content');
}

async function openSheet() {
  'background only';
  await nativeRouter.open({
    bundle: 'native-capabilities',
    presentation: 'sheet',
    transparent: true,
    params: { mode: 'sheet', source: 'main' },
  });
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

### 路由参数

```ts
interface NativeRouteOptions {
  bundle: string;
  presentation?: 'push' | 'modal' | 'sheet';
  transparent?: boolean;
  statusBarStyle?: 'dark-content' | 'light-content';
  params?: Record<string, unknown>;
}
```

`bundle` 必须匹配 `^[a-z0-9][a-z0-9-]*$`，并与 workspace `package.json` 的 `lynxBundle.name` 一致。路由页通过 init data 收到统一结构：

```json
{
  "route": {
    "bundle": "native-capabilities",
    "presentation": "sheet",
    "transparent": true,
    "statusBarStyle": "dark-content",
    "params": {
      "source": "main"
    }
  }
}
```

页面调用 `nativeRouter.close()` 返回上一层；根页面不会被关闭，并会返回错误。

### 状态栏样式

`statusBarStyle` 和 `nativeStatusBar.setStyle()` 描述的是状态栏前景，而不是页面背景：

- `dark-content`：深色图标和文字，适用于白色或其他浅色背景；
- `light-content`：白色图标和文字，适用于深色背景。

路由参数决定目标原生页面创建时的初始样式，默认是 `dark-content`；bridge 用于页面加载后动态切换当前页面。三个宿主都保持状态栏背景透明，让 Lynx 页面继续绘制到系统栏下面。路由 init data 中也包含 `route.statusBarStyle`，业务可以读取并保持自己的视觉状态一致。

### 返回拦截与进度

`NativeBackModule` 使用“预先启用 + 事件通知”的模型。共享层的
`nativeBackStack.addInterceptor()` 会在第一个拦截器入栈时启用原生返回，在最后一个
拦截器出栈时关闭。宿主不会在手势开始后等待异步 JavaScript 决定是否拦截。启用后，
栈顶业务必须处理 `commit`（关闭弹窗或调用 `nativeRouter.close()`），否则原生返回会被
消费而界面保持不动。

```tsx
useEffect(() => {
  'background only';
  const registration = nativeBackStack.addInterceptor((event) => {
    'background only';
    if (event.phase === 'progress') {
      // event.progress 为 0..1，可驱动 Lynx 自己的返回预览。
    }
    if (event.phase === 'commit') {
      nativeRouter.close();
    }
  });
  return registration.remove;
}, []);
```

拦截器按注册顺序组成后进先出栈。一次手势从 `start` 到 `cancel` / `commit` 固定交给
同一个栈顶拦截器；即使它在手势中途被移除，剩余事件也不会泄漏给下面的弹窗。关闭
顶层弹窗只会移除自己的注册项，下层弹窗自动成为新的栈顶，原生返回保持启用。

底层 `nativeBack.setEnabled()` 与 `nativeBack.addListener()` 仍保留给需要自行管理生命周期
的场景。普通弹窗、菜单和 sheet 应统一使用 `nativeBackStack`，不要混用两套生命周期。

统一事件名为 `nativeBack`，共享封装已经完成订阅和结构校验：

```ts
interface NativeBackEvent {
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

仓库中的 `Open stack demo` 会打开 `predictive-back-sheet`。每次 `Push Activity` 都通过 `presentation: 'sheet'` 新建一个透明原生页面，因此三层弹窗对应三层真实 Activity / ViewController / NavDestination，而不是在根 bundle 内绘制三层 overlay。每层只注册自己的返回拦截器；预测手势进度驱动当前全宽 sheet 向下位移，`commit` 退场完成后调用 `nativeRouter.close()`，从而露出下面一层原生页面。

这套行为已经封装在 `@lynx-template/activity-sheet`：`openActivityBottomSheet()` 负责以透明 sheet 路由打开目标 bundle，`useActivityBottomSheet()` 负责返回生命周期和关闭时序，`ActivityBottomSheet` 负责遮罩、全宽面板、grabber、动画与底部安全区。业务 bundle 只需要传入自己的内容；完整示例见 `lib/activity-sheet/README.md`。

每个新路由页都会重新注册五个 NativeModules，并继续注入 `nativeEnvironment.safeAreaInsets`。因此第二个 bundle 可以独立处理安全区、状态栏、返回接管和 WebSocket，也可以继续打开下一层 bundle。

## 业务 WebSocket

`NativeWebSocketModule` 是 App 自己维护的正式业务模块，与 Lynx DevTool 的 HMR
WebSocket 没有依赖关系。它在 Debug 和 Release 都会注册；Release 只允许
`wss://`，Debug 额外允许 `ws://` 用于局域网调试。

```ts
import { nativeWebSocket } from '@lynx-template/native-bridge';

function connectRealtime() {
  'background only';
  const socket = nativeWebSocket.connect({
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

`nativeWebSocket.connect()` 会立即返回连接对象，`opened` 在原生握手成功后完成，
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

仓库提供 `pnpm dev:websocket` 启动监听 `0.0.0.0:8787` 的文本/二进制 echo
服务。Debug bundle 可直接使用 `ws://电脑局域网IP:8787` 完成连接、发送、回显和
关闭验证；真机不能使用指向自身的 `localhost`。端口可通过 `LYNX_WS_PORT` 覆盖。

## 原生实现位置

- Android：`NativeKVModule.kt`、`NativeRouterModule.kt`、`NativeStatusBarModule.kt`、`NativeBackModule.kt`、`NativeWebSocketModule.kt`、`LynxPageActivity.kt`；
- iOS：`NativeModules/` 下的各模块、`LynxPageViewController.swift`；
- HarmonyOS：`native/` 下的各模块、`pages/Index.ets`。
