# @lynx-template/autolink-camera

三端 Camera Autolink 库，同时导出：

- `camera.takePhoto()`：打开 Android / iOS / HarmonyOS 的系统拍照界面；
- `<x-camera-view>`：三端原生内嵌相机，显示时自动申请权限；
- `cameraView.capture()` / `focusAtPoint()`：通过 Lynx UI Method 拍照、对焦和测光。

## 使用

消费 bundle 需要依赖本包，并在其 JSX 类型入口注册 Element（模板的
`bundle/main/src/components/native-elements.ts` 已完成）：

```ts
import type { CameraViewProps } from '@lynx-template/autolink-camera';

declare module '@lynx-js/types' {
  interface IntrinsicElements {
    'x-camera-view': CameraViewProps;
  }
}
```

系统相机：

```ts
import { camera } from '@lynx-template/autolink-camera';

const outcome = await camera.takePhoto({ lens: 'back' });
if (outcome.success && outcome.photo) {
  console.log(outcome.photo.uri, outcome.photo.width, outcome.photo.height);
}
```

系统相机的 `lens` 只是初始镜头偏好。系统 UI 没有跨平台的缩放、曝光或闪光灯参数协议；
Android 相机应用还可以忽略镜头提示。精确控制请使用内嵌 Element：

```tsx
import { cameraView } from '@lynx-template/autolink-camera';

<x-camera-view
  id="camera"
  style={{ width: '100%', height: '320px' }}
  active
  lens="back"
  zoom={1}
  torch="off"
  flash="auto"
  exposure-compensation={0}
  photo-quality={92}
  mirror-photo
  preview-fit="cover"
  bindready={(event) => console.log(event.detail)}
  bindstatechange={(event) => console.log(event.detail.state)}
  bindcapture={(event) => console.log(event.detail.photo.uri)}
  binderror={(event) => console.log(event.detail.code, event.detail.message)}
/>

const photo = await cameraView.capture('#camera');
await cameraView.focusAtPoint('#camera', 0.5, 0.5);
```

## Element 属性

| 属性 | 类型 / 默认值 | 说明 |
| --- | --- | --- |
| `active` | `boolean` / `true` | 启动或释放相机 session |
| `lens` | `back \| front` / `back` | 前后镜头；切换时原生重新配置 session |
| `zoom` | `number` / `1` | 缩放倍数，按 `ready` 事件报告的设备范围夹紧 |
| `torch` | `off \| on` / `off` | 持续补光灯；先检查 `ready.detail.torchSupported` |
| `flash` | `off \| on \| auto` / `auto` | `capture()` 的拍照闪光模式 |
| `exposure-compensation` | `number` / `0` | EV 补偿，按 `ready` 报告的范围夹紧 |
| `photo-quality` | `1..100` / `92` | 内嵌拍照 JPEG 质量 |
| `mirror-photo` | `boolean` / `true` | 是否水平镜像前置镜头成片 |
| `preview-fit` | `cover \| contain` / `cover` | `cover` 按比例填满并居中裁边；`contain` 完整显示并留黑边 |

`cover` 不拉伸画面，只裁剪实时预览超出 Element 的长边；返回 JPEG 保留相机传感器的
完整比例。`focusAtPoint` 坐标以 Element 左上角为 `(0, 0)`、右下角为 `(1, 1)`。

`ready`、`statechange`、`capture`、`error` 的强类型 detail，以及所有 public option / result
类型均从包根导出。拍照结果是 `{ uri, width, height, mimeType, sizeBytes }`，URI 指向缓存或
系统媒体位置，应视作不透明本地 URI；需要长期保留时再复制或保存到相册。

## 平台实现

- Android：系统 `ACTION_IMAGE_CAPTURE`；内嵌 CameraX `PreviewView` + `ImageCapture`；
- iOS：系统 `UIImagePickerController`；内嵌 AVFoundation session / preview / photo output；
- HarmonyOS：系统 Camera Picker；内嵌 CameraKit `PhotoSession` + ArkUI XComponent Surface。

原生实现、原始声明和生成 facade 分别位于 `android/`、`ios/`、`harmony/`、
`types/platform-native-module.d.ts` 与 `src/*.generated.ts`。修改 NativeModule ABI 后运行
`pnpm native:contracts:generate`；iOS 新接入后还需重新执行 `bundle exec pod install`。
