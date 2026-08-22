# Native Environment 数据契约

三端宿主都让 LynxView 覆盖完整窗口，背景可以绘制到系统栏下面；宿主再把不能放置可交互内容的区域通过 `initData` 传给 bundle。窗口几何变化时，宿主使用同一字段做增量更新，ReactLynx 的 `useInitData()` 会触发重渲染。

## Schema v1

```json
{
  "nativeEnvironment": {
    "schemaVersion": 1,
    "unit": "px",
    "safeAreaInsets": {
      "top": 24,
      "right": 0,
      "bottom": 20,
      "left": 0
    }
  }
}
```

这里的 `px` 是 Lynx 逻辑像素，而不是设备物理像素：iOS 使用 point，Android 将 WindowInsets 的物理像素除以 density，HarmonyOS 将 avoid area 从 px 转换为 vp。这样 bundle 不需要判断平台或再次换算。

`safeAreaInsets` 包含状态栏、导航栏/导航指示条和刘海/挖孔，四边取各来源的最大值。键盘不属于安全区：键盘高度和输入框避让应使用独立的可视窗口协议，避免键盘弹出时把整个页面永久当成新的安全区。

## Bundle 使用方式

`autolink/device` 的公共实现扩展了 ReactLynx 的 `InitData` 类型，并对缺失、负数和无效值回退为 `0`。所有 bundle 都从 `@lynx-template/autolink-device` 读取同一份宿主数据契约。页面保持最外层背景全屏，只在内容容器的 padding 上叠加安全区：

```ts
import { readSafeAreaInsets } from '@lynx-template/autolink-device';

const initData = useInitData();
const insets = readSafeAreaInsets(initData);

const style = {
  paddingTop: `${contentMargin.top + insets.top}px`,
  paddingRight: `${contentMargin.right + insets.right}px`,
  paddingBottom: `${contentMargin.bottom + insets.bottom}px`,
  paddingLeft: `${contentMargin.left + insets.left}px`,
};
```

新增 bundle 只需依赖 `@lynx-template/autolink-device`，即可复用同一类型与安全区读取函数；字段名称和含义应保持向后兼容。

## 三端数据源

- Android：`autolink/device` 的 `NativeEnvironmentBridge` 监听 `WindowInsetsCompat`，合并 system bars 与 display cutout，再换算为 dp；旋转、分屏和系统栏显隐会自动更新。
- iOS：`Device` 包读取 `UIView.safeAreaInsets` 并构造 template data；页面在 `viewSafeAreaInsetsDidChange()` 以及布局变化后发布更新，单位天然是 point。
- HarmonyOS：包内 `NativeSafeAreaController` 监听主窗口 `avoidAreaChange`，合并 system、cutout 与 navigation indicator，换算为 vp 后由页面更新 `LynxContext`。

宿主必须等到首个有效窗口几何值可用后再首次加载 bundle，不能先传零值并假设增量事件一定能修正首帧。每次重新加载内置、开发或热更新 bundle 时，也必须把当前值作为初始数据再次传入，不能只依赖前一个页面收到过的增量事件。后续窗口变化统一使用 Lynx 4.0 的 metadata 更新接口。
