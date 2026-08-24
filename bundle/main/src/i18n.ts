import type { AppLocale } from '@lynx-template/autolink-device';

type MessageValues = Record<string, string | number>;

let currentLocale: AppLocale = 'zh-Hans';

const english: Record<string, string> = {
  接口: 'APIs',
  接: 'API',
  'Lynx 接口能力展示': 'Lynx API Showcase',
  '以下将演示 Lynx 跨端接口能力，具体属性参数详见 Lynx 开发文档。所有接口在 Android / iOS / HarmonyOS 三端行为一致。':
    'Explore cross-platform Lynx APIs. See the Lynx documentation for detailed parameters; behavior is aligned across Android, iOS, and HarmonyOS.',
  组件: 'Components',
  组: 'UI',
  'Lynx UI 组件展示': 'Lynx UI Components',
  '以下组件来自官方无头组件库 @lynx-js/lynx-ui，iOS 上部分控件直接渲染原生 Liquid Glass 元素。':
    'These components use the official headless @lynx-js/lynx-ui library. On iOS, selected controls render as native Liquid Glass elements.',
  界面: 'Interface',
  界: 'UI',
  设备: 'Device',
  设: 'D',
  网络: 'Network',
  网: 'N',
  媒体: 'Media',
  媒: 'M',
  数据: 'Storage',
  数: 'S',
  基础组件: 'Basic',
  基: 'B',
  选择控件: 'Selection',
  选: 'C',
  反馈组件: 'Feedback',
  反: 'F',
  视图组件: 'Views',
  视: 'V',
  'overlay 浮层': 'Overlay',
  页面结果回传: 'Page Results',
  'Toast 提示': 'Toast',
  状态栏样式: 'Status Bar Style',
  屏幕亮度: 'Screen Brightness',
  本地通知: 'Local Notifications',
  通知: 'Notifications',
  相机: 'Camera',
  麦克风: 'Microphone',
  设备信息: 'Device Information',
  电池电量: 'Battery',
  传感器: 'Sensors',
  生物认证: 'Biometrics',
  运行时权限: 'Runtime Permissions',
  剪贴板: 'Clipboard',
  振动反馈: 'Haptics',
  扫码: 'Scanner',
  发起请求: 'Fetch',
  下载管理器: 'Download Manager',
  网络状态: 'Network Status',
  打开链接: 'Open URL',
  截图: 'Screenshot',
  系统分享: 'System Share',
  图片工具: 'Image Tooling',
  音频播放: 'Audio Player',
  录音: 'Audio Recorder',
  相册: 'Photo Library',
  'WebView 桥': 'WebView Bridge',
  'KV 写入': 'KV Write',
  'KV 读取': 'KV Read',
  振动: 'Haptics',
  'MMKV 存储': 'MMKV Storage',
  安全存储: 'Secure Storage',
  文件系统: 'File System',
  '按钮 Button': 'Button',
  按钮: 'Button',
  'Pressable 长按 / 触感': 'Pressable: Long Press / Haptics',
  '输入框 Input': 'Input',
  输入框: 'Input',
  '键盘适配 Keyboard': 'Keyboard Avoidance',
  键盘适配: 'Keyboard Avoidance',
  独立键盘弹窗: 'Keyboard Dialog',
  '滑块 Slider': 'Slider',
  滑块: 'Slider',
  '开关 Switch': 'Switch',
  开关: 'Switch',
  '多选 Checkbox': 'Checkbox',
  多选框: 'Checkbox',
  '单选 Radio': 'Radio',
  单选框: 'Radio',
  '下拉 Dropdown': 'Dropdown',
  下拉: 'Dropdown',
  预测返回弹层: 'Predictive Back Overlay',
  '对话框 Dialog': 'Dialog',
  对话框: 'Dialog',
  '底部弹层 Sheet': 'Bottom Sheet',
  底部弹层: 'Bottom Sheet',
  '轮播 Swiper': 'Swiper',
  轮播: 'Swiper',
  尚未操作: 'No action yet',
  尚未选择: 'Nothing selected',
  未设置: 'Not set',
  未连接: 'Disconnected',
  未开始录音: 'Recording has not started',
  加载中: 'Loading',
  '执行中…': 'Working…',
  '正在刷新…': 'Refreshing…',
  开始: 'Start',
  停止: 'Stop',
  暂停: 'Pause',
  继续: 'Resume',
  取消: 'Cancel',
  关闭: 'Close',
  删除: 'Delete',
  写入: 'Write',
  读取: 'Read',
  查询状态: 'Check Status',
  检查支持情况: 'Check Availability',
  重新查询: 'Refresh',
  已完成: 'Completed',
  已取消: 'Cancelled',
  已暂停: 'Paused',
  已连接: 'Connected',
  已授权: 'Granted',
  已拒绝: 'Denied',
  未请求: 'Not Requested',
  部分授权: 'Limited',
  受系统限制: 'Restricted',
  支持: 'Supported',
  不支持: 'Not Supported',
  可用: 'Available',
  不可用: 'Unavailable',
  成功提示: 'Success',
  失败提示: 'Failure',
  默认提示: 'Default',
  消息提示: 'Message',
  已弹出: 'Shown',
  这是一条默认提示: 'This is a default message',
  保存成功: 'Saved successfully',
  '操作失败，请重试': 'The operation failed. Try again.',
  '自定义背景色，3 秒消失': 'Custom background; disappears in 3 seconds',
  立即通知: 'Immediate',
  '5 秒定时': 'In 5 Seconds',
  '未获得通知权限（{status}）':
    'Notification permission not granted ({status})',
  'Lynx 本地通知': 'Lynx Notification',
  'Lynx 定时通知': 'Scheduled Lynx Notification',
  '来自 LocalNotification 模块的即时通知。':
    'An immediate notification from the LocalNotification module.',
  '这条通知在 5 秒前由 AlarmManager / 系统触发器排期。':
    'This notification was scheduled 5 seconds earlier by AlarmManager or the system scheduler.',
  '已发送（或已排期）': 'Sent or scheduled',
  已取消排期与已送达: 'Cancelled scheduled and delivered notifications',
  全部取消: 'Cancel All',
  已清除本应用通知: 'Cleared this app’s notifications',
  'Lynx 接口演示': 'Lynx API Demo',
  '请通过设备可用的生物认证继续。':
    'Authenticate using an available biometric method to continue.',
  '请通过生物认证完成签名。': 'Authenticate to complete signing.',
  'Lynx 下载演示': 'Lynx Download Demo',
  下载将在应用进入后台后继续:
    'The download will continue while the app is in the background',
  '来自 Lynx Template 的系统分享：三端一致的分享面板 API。':
    'Shared from Lynx Template using the same system share API on all three platforms.',
  'Lynx 跨端框架': 'Lynx cross-platform framework',
  'Lynx 截图': 'Lynx Screenshot',
  'screenshot.capture 的产物直接交给分享面板':
    'Output from screenshot.capture shared directly through the system sheet',
  浅色文字: 'Light Content',
  深色文字: 'Dark Content',
  请输入内容: 'Enter text',
  '输入内容…': 'Enter text…',
  '写点什么…': 'Write something…',
  请选择一个模式: 'Choose a mode',
  三端独立键盘弹窗: 'Cross-platform Keyboard Dialog',
  全屏页面: 'Full-screen Page',
  创建下载任务: 'Create Download',
  加速度计: 'Accelerometer',
  单行输入框: 'Single-line Input',
  原生跟手底部弹层: 'Native Interactive Sheet',
  变化监听: 'Change Listener',
  多行输入框: 'Multiline Input',
  平台下拉: 'Platform Dropdown',
  平台能力: 'Platform Capability',
  当前网络: 'Current Network',
  指南针: 'Compass',
  陀螺仪: 'Gyroscope',
  磁力计: 'Magnetometer',
  气压计: 'Barometer',
  测试方式: 'Test Method',
  '滚动 / 甩动 / 刹停验证': 'Scroll / Fling / Stop Test',
  硬件签名密钥: 'Hardware Signing Key',
  禁用状态: 'Disabled State',
  缓存沙箱读写: 'Cache Sandbox I/O',
  '裁剪、拼图与 EXIF 管线': 'Crop, Compose, and EXIF Pipeline',
  连续滑块: 'Continuous Slider',
  选择一种水果: 'Choose a Fruit',
  选择页: 'Picker Page',
  键盘状态: 'Keyboard State',
  长按与系统触感: 'Long Press and System Haptics',
  页面中部输入框: 'Middle Input',
  页面底部输入框: 'Bottom Input',
  验证要点: 'What to Verify',
  'Lynx UI 开关': 'Lynx UI Switch',
  'MMKV 键值存储': 'MMKV Key-value Storage',
  'WebView 模块桥': 'WebView Module Bridge',
  '@lynx-js/lynx-ui 的无头按钮：自带按下态（ui-active）与禁用态（ui-disabled）CSS 变体，样式完全自定义。':
    'A headless @lynx-js/lynx-ui button with ui-active and ui-disabled CSS states and fully custom styling.',
  'Android Keystore 加密 / iOS Keychain / 鸿蒙 HUKS，适合 Token 等短小机密（最长 64KB）。':
    'Encrypted with Android Keystore, iOS Keychain, or HarmonyOS HUKS; intended for small secrets such as tokens (up to 64 KB).',
  'Bundle 内直接使用标准 fetch；三端宿主分别用 OkHttp / URLSession / Network Kit 传输，Debug 允许 http，Release 仅 https。':
    'Use standard fetch directly in the bundle. Android, iOS, and HarmonyOS transport through OkHttp, URLSession, and Network Kit; Debug permits HTTP while Release requires HTTPS.',
  'PageFrame 开启 keyboardAware；每个输入目标由 KeyboardAwareTrigger 标记。':
    'PageFrame enables keyboardAware, and each focus target is marked with KeyboardAwareTrigger.',
  'RadioGroupRoot 管理整组选中值，Radio + RadioIndicator 组成单个选项。':
    'RadioGroupRoot owns the selected value; each option combines Radio and RadioIndicator.',
  'TextArea 支持多行文本输入。': 'TextArea supports multiline text input.',
  'disabled 后滑块不再响应手势。':
    'The slider no longer responds to gestures while disabled.',
  'inputDialog 使用独立原生覆盖层适配键盘，不会重排后面的页面。Android 固定 resize；点击空白或返回时，待键盘收起后再关闭。':
    'inputDialog uses a separate native overlay for keyboard adaptation without relayout of the page behind it. Android uses resize; backdrop taps and Back wait for the keyboard to hide before closing.',
  'openForResult 的参数与 open 一致，但其 Promise 会等到打开的页面真正关闭才 resolve；对方调用 closeWithResult 则 resolve 为结果对象，直接返回或系统返回手势则 resolve 为 undefined，打开失败会 reject。':
    'openForResult accepts the same options as open, but its Promise resolves only when the opened page closes. closeWithResult returns an object; direct or system Back returns undefined; open failures reject.',
  'useKeyboard() 将 keyboardstatuschanged 归一化为类型化的 visible 与 height。':
    'useKeyboard() normalizes keyboardstatuschanged into typed visible and height values.',
  '三档物理触感反馈，适合配合按钮点击、开关切换等轻交互。':
    'Three physical haptic levels for lightweight interactions such as buttons and switches.',
  '主线程驱动的横滑轮播：跟手滑动、惯性吸附，支持程序化切换与指示点。':
    'A main-thread horizontal swiper with interactive dragging, inertial snapping, programmatic navigation, and page dots.',
  '从屏幕底部升起的弹层：支持吸附点、拖拽手势与点击遮罩关闭，手势由主线程驱动。':
    'A bottom sheet with snap points, drag gestures, and backdrop dismissal, driven on the main thread.',
  '从系统文件选择器挑选一个本地音频文件播放；进度与状态经 audioPlayer 事件回传，音频焦点由原生按 media 流自动管理。':
    'Pick a local audio file with the system picker. Progress and state arrive through audioPlayer events, while native code manages media audio focus.',
  '先由统一接口探测当前宿主执行模式；Android 额外提供 dataSync 前台服务。':
    'The shared API first detects the current host mode; Android additionally offers a dataSync foreground service.',
  '先申请麦克风权限，再录制 AAC(m4a) 音频写入应用缓存目录；状态与时长经 audioRecorder 事件回传，上限 60 秒自动停止，录完可直接回放。':
    'Request microphone permission, then record AAC (m4a) into the app cache. audioRecorder events report state and duration, recording stops at 60 seconds, and the result can be played immediately.',
  '先观察上方状态，再滚动到页面底部并聚焦多行输入框。键盘弹出后，PageFrame 会自动滚动，避免输入框被遮挡。':
    'Watch the state above, scroll to the bottom, and focus the multiline field. PageFrame scrolls automatically to keep it above the keyboard.',
  '全屏相机扫码页，支持二维码 / 条码；取消、无权限、图中无码都会以结果码返回。':
    'A full-screen camera scanner for QR codes and barcodes. Cancellation, missing permission, and no-code results all return explicit result codes.',
  '内嵌网页通过 window.__lynxNativeBridge 调用与 Lynx 侧相同的原生模块（存储 / 剪贴板 / 振动 / 设备信息），三端宿主行为一致。加载完成后页面会自动跑一轮自检。':
    'The embedded page calls the same native modules as Lynx through window.__lynxNativeBridge (storage, clipboard, haptics, and device info). It runs a self-test after loading.',
  '写入与读取系统剪贴板文本。':
    'Write and read text through the system clipboard.',
  '分别长按下面两个按钮：约 500ms 后只回调一次 longpress，松手不会补发 press；第二个按钮还会触发系统线性马达。':
    'Long-press both buttons. After about 500 ms, longpress fires once and release does not add press; the second button also triggers system haptics.',
  '切换系统状态栏前景色：深色文字适合浅色背景，浅色文字适合深色背景。':
    'Switch the system status-bar foreground: dark content for light backgrounds and light content for dark backgrounds.',
  '原生 MMKV 高性能键值存储，适合缓存与小数据持久化，跨启动保留；inMemory 写入只改进程内 overlay，读取时优先命中。':
    'Native high-performance MMKV key-value storage for caches and small persistent data. inMemory writes affect only the process overlay and take precedence when reading.',
  '受控输入：onInput 回传最新文本，可设置 placeholder。':
    'Controlled input: onInput returns the latest text and placeholder is configurable.',
  '在应用缓存沙箱内写入文本与二进制文件、列目录、删除目录；路径只能落在沙箱内。':
    'Write text and binary files, list directories, and remove directories inside the app cache sandbox. Paths cannot escape the sandbox.',
  '外观和出现 / 消失节奏对齐 LynxUI Sheet。Android / iOS 的系统返回和向下拖动都在 UI 线程直接更新位移与遮罩，不会逐帧跨桥调用 JavaScript。':
    'Appearance and timing match LynxUI Sheet. Android and iOS Back and drag-down gestures update translation and scrim directly on the UI thread without per-frame JavaScript bridge calls.',
  '应用自有的全双工长连接（不依赖 DevTool 调试通道）；事件通过 GlobalEventEmitter 分发。':
    'An app-owned full-duplex connection independent of the DevTool channel; events are distributed through GlobalEventEmitter.',
  '开启进度落盘的任务会跨进程保留；中断时的 queued/running 状态统一恢复为 paused，不会在初始化时自动联网。':
    'Tasks with persisted progress survive process restarts. Interrupted queued or running tasks restore as paused and do not access the network during initialization.',
  '打开前对当前页面截图，新页面首帧即以截图为背景（与上一页像素一致、无闪白）。默认内容不做透明度变化，从屏幕下方 0 可见面积推入，关闭时再推出；入场、出场以及 iOS/Android 的交互返回都可单独配置。':
    'Capture the current page before opening so the new page starts over a pixel-matched snapshot without a white flash. Content pushes in from below and pushes out on close; enter, exit, and iOS/Android interactive Back behavior are independently configurable.',
  '把 URL 交给系统路由解析：https 走浏览器，自定义 scheme 唤起注册了该 scheme 的应用。':
    'Let the system resolve a URL: HTTPS opens in a browser, while custom schemes launch an app registered for that scheme.',
  '把指定卡片、整个 LynxView 或原生页面截为 PNG/JPEG，写入应用缓存目录。':
    'Capture a card, the complete LynxView, or the native page as PNG/JPEG in the app cache.',
  '拖动或点按轨道改变数值，主线程手势驱动，跟手不掉帧。':
    'Drag or tap the track to change the value. Main-thread gestures keep interaction smooth.',
  '持续输出包含重力的 x/y/z 加速度（m/s²）。':
    'Continuously reports gravity-inclusive x/y/z acceleration in m/s².',
  '持续输出绕 x/y/z 轴的角速度（rad/s）。':
    'Continuously reports the angular velocity around the x/y/z axes in rad/s.',
  '持续输出设备坐标系下的地磁强度（µT）。':
    'Continuously reports the geomagnetic field strength in the device frame in µT.',
  '输出环境气压（hPa），数值随海拔与天气缓慢变化。':
    'Reports ambient barometric pressure in hPa; the value drifts slowly with altitude and weather.',
  '按 scope 创建可轮换的不可导出密钥；签名绑定 keyId、业务上下文摘要与服务端挑战。':
    'Create a rotatable, non-exportable key per scope. Signatures bind the key ID, business-context digest, and server challenge.',
  '无头多选组件，指示器内容完全自定义；这里绘制了一个绿色对勾。':
    'A headless checkbox with fully custom indicator content; this demo draws a green checkmark.',
  '无头开关组件：轨道与滑块自由布局，ui-checked / ui-active 变体驱动过渡动画。':
    'A headless switch with freely composed track and thumb; ui-checked and ui-active states drive transitions.',
  '机型、系统版本、应用版本与包名、屏幕密度、地区语言与三种宽度（屏幕 / 窗口 / LynxView）。':
    'Hardware model, OS and app versions, application id, display density, locale, and screen, window, and LynxView widths.',
  '模态对话框：Backdrop 遮罩 + Content 内容 + Trigger / Close 触发器，支持受控开关。对话框打开期间系统返回先关闭对话框，而不是退出页面。':
    'A controlled modal composed from Backdrop, Content, Trigger, and Close. System Back closes the dialog before leaving the page.',
  '横幅也支持长按，但未开启马达。慢拖、快速甩动或点停惯性都不应触发点击/长按。':
    'The banner supports long press without haptics. Slow drags, quick flings, and stopping inertia should not trigger press or longpress.',
  '演示任务会开启 persistProgress。杀死 App 后再次进入本页，任务将恢复为暂停态，点击“继续”才会重新下载。默认地址是支持 Range 的 100 MB 公共测试文件。':
    'Demo tasks enable persistProgress. After restarting the app, a task restores as paused and downloads only after Resume. The default is a public 100 MB Range-enabled test file.',
  '磁北朝向 0-360°；iOS 首次使用会请求定位权限。':
    'Magnetic-north heading from 0–360°. iOS requests location permission on first use.',
  '窗口内的原生 Toast：可自定义颜色与图标，无需通知权限，新的 Toast 会替换上一条。':
    'A native in-window Toast with configurable color and icon. It needs no notification permission, and a new Toast replaces the previous one.',
  '窗口级亮度 0-100%：应用前台期间生效，退后台后系统恢复；常亮仅在本应用可见时保持。':
    'Window brightness from 0–100% applies while the app is foregrounded and restores in the background. Keep-awake applies only while this app is visible.',
  '第一个监听者注册原生监听并立即回推当前快照，最后一个取消时移除。可切换飞行模式 / Wi-Fi 观察事件流。':
    'The first subscriber installs the native listener and receives an immediate snapshot; the last unsubscribe removes it. Toggle Airplane Mode or Wi-Fi to observe events.',
  '系统文件选择器选取任意文件，stat 读取元数据，readText 读取前 4KB 文本内容。':
    'Pick any file with the system picker; stat reads metadata and readText previews the first 4 KB.',
  '统一的权限查询与申请：状态归一为已授权/部分授权/已拒绝/未请求/受限制。Android 无法区分「未请求」与「拒绝后不再询问」，因此 denied 后申请仍可能弹窗；iOS 拒绝后需去系统设置。':
    'Unified permission query and request states: granted, limited, denied, not requested, or restricted. Android cannot distinguish not-requested from some denied states; iOS denial must be changed in Settings.',
  '读取当前电量百分比与充电状态。':
    'Read the current battery percentage and charging state.',
  '调用系统相册选择器挑选图片（最多 3 张），并通过 fileSystem.stat 读取文件元数据。':
    'Pick up to three images with the system photo picker and read their metadata through fileSystem.stat.',
  '调起系统分享面板发送文本、链接与本地文件。iOS 报告真实送达/取消与目标；Android 报告选中目标包名，取消为尽力检测；HarmonyOS 只报告面板关闭。':
    'Share text, URLs, and local files through the system sheet. iOS reports completion, cancellation, and target; Android reports the selected package with best-effort cancellation; HarmonyOS reports sheet closure.',
  '这个输入框用于验证自动滚动与额外的 16px 避让距离。':
    'This field verifies automatic scrolling and the additional 16 px clearance.',
  '这个页面由 overlay Sheet 内再次调用 router.open 打开，是导航栈中的普通全屏路由；关闭后会回到原来的 Sheet。':
    'This ordinary full-screen route is opened with router.open from inside an overlay sheet. Closing returns to that sheet.',
  '进入页面自动执行：读取/压缩 → 中心裁剪 → 横拼、竖拼、透明叠加（均限制 maxWidth/maxHeight）→ 写入/读取/定点删除/全量清除 EXIF。GPS 使用固定的 0,0 测试值，不读取设备位置。':
    'Runs automatically: read/compress → center crop → horizontal and vertical composition plus transparent overlay → write, read, selectively remove, and clear EXIF. GPS uses a fixed 0,0 test value and never reads device location.',
  '进入页面自动查询一次；type 为 wifi / cellular / ethernet / other / none，cellularGeneration 由平台能力决定（Android 需 READ_PHONE_STATE）。':
    'Queries once on entry. type is wifi, cellular, ethernet, other, or none; cellularGeneration depends on platform capability (Android requires READ_PHONE_STATE).',
  '连续打开两层后，第一次返回或下拉只关闭第二层，第二次才关闭第一层。下拉距离不足时会原生回弹且不会出栈。':
    'After opening two layers, the first Back or drag closes only the second and the next closes the first. An incomplete drag springs back natively without popping.',
  '选择任意一项会以 closeWithResult 携带结果关闭本页；“直接返回”与系统返回手势都不携带结果。也可以从这里再打开一层选择页，验证嵌套等待。':
    'Choosing an item closes with a closeWithResult payload. Direct and system Back return no result. Open another picker here to verify nested waiting.',
  '通过系统通知中心发送通知：权限申请走 Permissions 模块；定时通知在 Android 用 AlarmManager 排期（App 被杀后仍会送达），HarmonyOS 为进程内定时。':
    'Send through the system notification center. Permission uses the Permissions module; Android schedules with AlarmManager even after process death, while HarmonyOS timers are in-process.',
  '静默能力检查 + 一次系统认证弹窗；设备会使用已配置的人脸或指纹，业务无需也不能指定传感器。':
    'A silent capability check plus one system authentication prompt. The device chooses its configured face or fingerprint sensor.',
  'Android 预测返回下移': 'Android Predictive Back Drag',
  'iOS 侧滑下移退出': 'iOS Edge-swipe Dismiss',
  上一张: 'Previous',
  下一张: 'Next',
  丢弃重录: 'Discard and Record Again',
  仅内容入出场: 'Content Transition Only',
  仅背景缩放: 'Backdrop Scale Only',
  从相册选图识别: 'Scan from Photo',
  从相册选择图片: 'Choose Photos',
  从相册选择图片验证: 'Choose a Photo to Verify',
  '以 overlay 打开': 'Open as Overlay',
  停止并保存: 'Stop and Save',
  '入场仅淡入 / 出场默认推出': 'Fade In / Default Push Out',
  '入场默认推入 / 出场仅淡出': 'Default Push In / Fade Out',
  '关闭 Sheet': 'Close Sheet',
  关闭全屏页面: 'Close Full-screen Page',
  关闭弹层: 'Close Overlay',
  '关闭栈顶，保留第一层': 'Close Top Layer, Keep First',
  '写入(仅内存)': 'Write (Memory Only)',
  写入二进制并回读: 'Write and Read Binary',
  写入文本: 'Write Text',
  写入随机文本: 'Write Random Text',
  分享文本: 'Share Text',
  分享链接: 'Share URL',
  列目录: 'List Directory',
  删除当前密钥: 'Delete Current Key',
  删除目录: 'Remove Directory',
  '前进 10 秒': 'Forward 10 Seconds',
  加密写入: 'Write Encrypted Value',
  发起生物认证: 'Authenticate',
  '发送 5 秒定时通知': 'Schedule in 5 Seconds',
  发送一条消息: 'Send a Message',
  发送立即通知: 'Send Now',
  取消全部: 'Cancel All',
  取消定时通知: 'Cancel Scheduled Notification',
  '后退 10 秒': 'Back 10 Seconds',
  回放刚录的: 'Play Recording',
  在上方再打开第二层: 'Open a Second Layer Above',
  开始应用内下载: 'Start In-app Download',
  开始录音: 'Start Recording',
  弹出申请: 'Request Permission',
  截取上方卡片: 'Capture Card Above',
  截取原生页面: 'Capture Native Page',
  '截取整个 LynxView': 'Capture Full LynxView',
  截图并分享: 'Capture and Share',
  '打开 https://www.lynxjs.org': 'Open https://www.lynxjs.org',
  打开全屏页面: 'Open Full-screen Page',
  打开底部弹层: 'Open Bottom Sheet',
  打开独立键盘弹窗: 'Open Keyboard Dialog',
  打开相机扫码: 'Open Camera Scanner',
  打开第一层弹层: 'Open First Layer',
  打开选择页等待结果: 'Open Picker and Await Result',
  '提高 10%': 'Increase 10%',
  断开连接: 'Disconnect',
  查看沙箱根目录: 'View Sandbox Root',
  '模糊背景（降采样截图）': 'Blurred Backdrop (Downsampled Snapshot)',
  清除全部动画: 'Disable All Animations',
  生成签名密钥: 'Create Signing Key',
  直接关闭第一层: 'Close First Layer Directly',
  '直接返回（不携带结果）': 'Go Back Without a Result',
  签名挑战: 'Sign Challenge',
  '自定义遮罩 #99CC3300': 'Custom Scrim #99CC3300',
  '自定义颜色 · 无图标': 'Custom Color · No Icon',
  读取剪贴板: 'Read Clipboard',
  读取当前亮度: 'Read Brightness',
  读取电量: 'Read Battery',
  读取设备信息: 'Read Device Info',
  '选图并分享（最多 3 张）': 'Choose and Share Photos (Up to 3)',
  选择文件并读取: 'Choose and Read File',
  选择音频文件: 'Choose Audio File',
  '长按测试，不带系统触感': 'Long Press Without Haptics',
  '长按测试，带系统触感': 'Long Press With Haptics',
  '降低 10%': 'Decrease 10%',
  '页面下拉退出（三端）': 'Drag Down to Dismiss (All Platforms)',
  '先写入，再读取验证': 'Write first, then read to verify',
  '写入 / 列出 / 删除缓存沙箱文件':
    'Write, list, and remove files in the cache sandbox',
  '写入 → 读取 → 删除 完整闭环': 'Write → Read → Delete end-to-end',
  分享结果展示在这里: 'Share results appear here',
  加密写入后可读取验证: 'Write encrypted data, then read to verify',
  发起一次系统生物认证: 'Start system biometric authentication',
  发送结果会显示在这里: 'Send results appear here',
  '可验证 iOS 边缘侧滑、Android 返回手势或页面纵向下拉':
    'Verify iOS edge swipe, Android Back gesture, or vertical page drag',
  '启动后可终止 App；重开后刷新列表并手动继续':
    'Terminate the app after starting; reopen, refresh, and resume manually',
  多行输入内容统计: 'Multiline input statistics',
  '尚未收到事件；请分别长按两个按钮进行对比':
    'No events yet; long-press both buttons to compare',
  尚未选择任何支付方式: 'No payment method selected',
  开始后可晃动设备观察数值: 'Start, then shake the device to observe values',
  开始后旋转设备观察朝向: 'Start, then rotate the device to observe heading',
  开始后转动设备观察角速度:
    'Start, then rotate the device to observe rotation rate',
  开始后转动设备观察磁场变化:
    'Start, then rotate the device to observe field changes',
  开始后读取当前环境气压: 'Start to read the current ambient pressure',
  录音状态与结果展示在这里: 'Recording status and results appear here',
  '截图结果（尺寸与文件）展示在这里':
    'Capture size and file results appear here',
  打开后试试拖拽与遮罩关闭: 'Open it, then try dragging and backdrop dismissal',
  扫码结果展示在这里: 'Scan results appear here',
  播放状态与进度: 'Playback state and progress',
  暂无下载任务: 'No download tasks',
  查询或申请一项权限: 'Query or request a permission',
  '正在探测下载能力…': 'Detecting download capability…',
  '正在查询网络状态…': 'Checking network state…',
  '点击上方按钮弹出 Toast': 'Tap a button above to show a Toast',
  点击任意按钮查看事件: 'Tap any button to inspect events',
  点击发送时自动申请通知权限:
    'Notification permission is requested automatically when sending',
  点击感受不同强度的振动: 'Tap to feel different haptic strengths',
  点击按钮打开一个模态对话框: 'Tap the button to open a modal dialog',
  点击读取本机信息: 'Tap to read device information',
  点击读取电池状态: 'Tap to read battery state',
  聚焦输入框后观察键盘避让效果: 'Focus an input to observe keyboard avoidance',
  观察页面顶部状态栏变化: 'Watch the status bar at the top',
  读取或调整窗口亮度: 'Read or adjust window brightness',
  输入内容实时展示在这里: 'Input is reflected here in real time',
  输入姓名: 'Enter a name',
  '输入较长的备注…': 'Enter a longer note…',
  返回生命周期事件会显示在这里: 'Back lifecycle events appear here',
  '选中图片的名称 / 大小 / 类型': 'Selected photo name, size, and type',
  选中文件的元数据与文本预览: 'Selected file metadata and text preview',
  '选择一个目标发起 GET 请求': 'Choose a target for a GET request',
  选择一个链接交给系统打开: 'Choose a URL for the system to open',
  链接可达性: 'URL Availability',
  'canOpen 先探测系统里是否有应用能处理该 URL；未在宿主声明的第三方 scheme 会返回 false。':
    'canOpen first probes whether any installed app can handle the URL; third-party schemes not declared by the host resolve to false.',
  '检测 {url}': 'Check {url}',
  有可处理的应用: 'A handler is available',
  没有应用可处理: 'No handler is available',
  '检测失败：{message}': 'Check failed: {message}',
  检测结果展示在这里: 'Check results appear here',
  打开应用设置: 'Open App Settings',
  已请求打开系统应用设置: 'Requested the system app settings page',
  '选择一项、点直接返回或用系统返回手势，观察结果差异':
    'Choose an item, go back directly, or use the system Back gesture to compare results',
  事件日志展示在这里: 'Event logs appear here',
  排队中: 'Queued',
  下载中: 'Downloading',
  失败: 'Failed',
  'Android 前台服务': 'Android Foreground Service',
  应用内任务: 'In-app Task',
  进度落盘: 'Persist Progress',
  仅进程内: 'Process Only',
  '文件：{uri}': 'File: {uri}',
  打开对话框: 'Open Dialog',
  '删除这条记录？': 'Delete this record?',
  '删除后无法恢复，请确认该操作是你本人发起。':
    'This cannot be undone. Confirm that you initiated this action.',
  '可以拖动顶部的把手调整高度，或点击遮罩区域关闭。':
    'Drag the handle to adjust the height, or tap the backdrop to close.',
  打开第一层: 'Open First Layer',
  叠加第二层: 'Add Second Layer',
  逐层返回: 'Back Through Layers',
  '• 后进先出（LIFO）': '• Last in, first out (LIFO)',
  '• 单次手势固定消费同一层': '• One gesture always consumes one layer',
  '• Android / iOS 原生逐帧动画':
    '• Native per-frame animation on Android / iOS',
  '• 下拉超过阈值关闭，否则回弹':
    '• Close past the drag threshold; otherwise spring back',
  '返回栈 · 第 1 层': 'Back Stack · Layer 1',
  '返回栈 · 第 2 层（栈顶）': 'Back Stack · Layer 2 (Top)',
  栈顶弹层: 'Top Sheet',
  '向下拖动会跟随手指移动；松手后超过阈值关闭，否则回弹。也可以继续打开第二层，验证返回栈顺序。':
    'Drag down to follow your finger. Release past the threshold to close, otherwise it springs back. Open a second layer to verify stack order.',
  '这是当前栈顶。系统返回、点击遮罩或向下拖动都只会关闭这一层，下面的第一层不会被同一次操作消费。':
    'This is the top of the stack. System Back, backdrop tap, or drag-down closes only this layer; the first layer remains.',
  我是被截取的卡片区域: 'This card area will be captured',
  执行日志展示在这里: 'Execution logs appear here',
  叠加预览: 'Composite Preview',
  '背后露出的“上一页”是打开瞬间截取的截图背景；系统返回、点按遮罩或下方按钮都会先放大复原背景，再无缝切回真实的上一页。':
    'The previous page visible behind this sheet is a snapshot captured on open. Back, a backdrop tap, or the button below restores it before seamlessly returning to the live page.',
  主要按钮: 'Primary Button',
  次要按钮: 'Secondary Button',
  警示操作: 'Destructive Action',
  '1　聚焦任意输入框': '1  Focus any input',
  '2　观察 visible 和 height': '2  Observe visible and height',
  '3　关闭键盘并确认页面复位': '3  Hide the keyboard and verify reset',
  写一条评论: 'Write a Comment',
  发送: 'Send',
  '长按测试（无触感）': 'Long Press (No Haptics)',
  '长按测试（系统触感）': 'Long Press (System Haptics)',
  已开启: 'On',
  已关闭: 'Off',
  微信: 'WeChat',
  支付宝: 'Alipay',
  云闪付: 'UnionPay',
  标准模式: 'Standard',
  长辈模式: 'Senior',
  青少年模式: 'Teen',
  苹果: 'Apple',
  香蕉: 'Banana',
  樱桃: 'Cherry',
  榴莲: 'Durian',
  蓝莓: 'Blueberry',
  '点击 Lynx 按钮打开原生 Liquid Glass 菜单':
    'Tap the Lynx button to open the native Liquid Glass menu',
  第一屏: 'Page One',
  第二屏: 'Page Two',
  第三屏: 'Page Three',
  第四屏: 'Page Four',
  夏日限定: 'Summer Special',
  按住可看原生状态层反馈: 'Hold to see native pressed-state feedback',
  新品首发: 'New Release',
  上下拖动时不会进入按下态:
    'Vertical dragging does not enter the pressed state',
  会员专享: 'Members Only',
  快速甩动后点按可验证惯性刹停:
    'Tap after a quick fling to test inertial stopping',
  周末活动: 'Weekend Event',
  '滚动手势最终不会发出 press': 'A scroll gesture never emits press',
  精选内容: 'Featured',
  只有完整原生点击才跨线程回调:
    'Only a completed native tap sends a cross-thread callback',
  附近推荐: 'Nearby',
  '移动超过平台 touch slop 即取消':
    'Movement beyond the platform touch slop cancels the gesture',
  订阅更新: 'Subscription Update',
  'ACTION_CANCEL / touchesCancelled 会复位':
    'ACTION_CANCEL / touchesCancelled resets state',
  热门榜单: 'Trending',
  '视觉反馈不触发 React 重新渲染':
    'Visual feedback does not trigger a React re-render',
  创作者计划: 'Creator Program',
  'Android、iOS、HarmonyOS 同一标签':
    'The same label on Android, iOS, and HarmonyOS',
  更多内容: 'More Content',
  继续滚动以测试长列表行为: 'Keep scrolling to test long-list behavior',

  // Dynamic result and diagnostic messages. Placeholders also let t()
  // translate a fully formatted source string at the shared render boundary.
  '正在请求 {url} …': 'Requesting {url}…',
  'HTTP {status} · {bytes} 字节\n{body}':
    'HTTP {status} · {bytes} bytes\n{body}',
  '请求失败：{message}': 'Request failed: {message}',
  '→ 连接 {url}': '→ Connecting to {url}',
  '← 已连接（echo 服务器会原样回发）':
    '← Connected (the echo server returns the same payload)',
  '← 收到：{data}': '← Received: {data}',
  '! 错误：{message}': '! Error: {message}',
  '← 已关闭 code={code}（正常）': '← Closed code={code} (clean)',
  '← 已关闭 code={code}（异常）': '← Closed code={code} (unclean)',
  '! 连接失败：{message}': '! Connection failed: {message}',
  '! 尚未连接': '! Not connected',
  '→ 发送：{payload}': '→ Sent: {payload}',
  '! 发送失败：{message}': '! Send failed: {message}',
  '已交给系统处理：{url}': 'Handed off to the system: {url}',
  '打开失败：{message}': 'Open failed: {message}',
  '打开失败: {message}': 'Open failed: {message}',
  '{connection} · {type} · 代际 {generation} · {time}':
    '{connection} · {type} · generation {generation} · {time}',
  '查询失败：{message}': 'Query failed: {message}',
  '→ 开始监听网络变化': '→ Started observing network changes',

  '已选择：{items}': 'Selected: {items}',
  '当前：{value}': 'Current: {value}',
  '已选择：{item}（第 {index} 项）': 'Selected: {item} (item {index})',
  '选择 {item}': 'Choose {item}',
  青柠绿: 'Lime Green',
  天空蓝: 'Sky Blue',
  琥珀橙: 'Amber Orange',
  '跟手下拉关闭：{state}': 'Interactive drag dismissal: {state}',
  '{layer}：返回{phase} · {source}{gesture}':
    '{layer}: Back {phase} · {source}{gesture}',
  第一层: 'Layer 1',
  第二层: 'Layer 2',
  进行中: 'in progress',
  取消并复位: 'cancelled and reset',
  提交关闭: 'committed close',
  尚未打开弹层: 'No overlay opened yet',
  '第一层已打开；返回会先消费这一层':
    'Layer 1 is open; Back will consume this layer first',
  '第二层已入栈；下一次返回只关闭第二层':
    'Layer 2 is on the stack; the next Back closes only Layer 2',
  第一层由页面按钮关闭: 'Layer 1 was closed by the page button',
  '第二层由页面按钮关闭，第一层仍然保留':
    'Layer 2 was closed by the page button; Layer 1 remains',
  '返回已关闭第一层；返回栈现在为空':
    'Back closed Layer 1; the Back stack is now empty',
  点击遮罩关闭了第一层: 'A backdrop tap closed Layer 1',
  向下拖动关闭了第一层: 'A downward drag closed Layer 1',
  '返回只关闭了栈顶第二层；第一层仍然打开':
    'Back closed only the top Layer 2; Layer 1 remains open',
  '点击遮罩关闭了第二层；第一层仍然打开':
    'A backdrop tap closed Layer 2; Layer 1 remains open',
  '向下拖动关闭了第二层；第一层仍然打开':
    'A downward drag closed Layer 2; Layer 1 remains open',

  '已写入 {key} = {value}': 'Wrote {key} = {value}',
  '已写入内存 {key} = {value}（MMKV 旧值保留）':
    'Wrote {key} = {value} in memory (the previous MMKV value remains)',
  '读到 {key} = {value}': 'Read {key} = {value}',
  '已删除 {key}': 'Deleted {key}',
  '已加密写入 {key} = {value}': 'Wrote encrypted {key} = {value}',
  'MMKV 中暂无数据': 'No data in MMKV',
  安全存储中暂无数据: 'No data in secure storage',
  未知类型: 'Unknown type',
  '{header}\n文本预览：{preview}': '{header}\nText preview: {preview}',
  '{header}\n（二进制文件，跳过文本预览）':
    '{header}\n(Binary file; text preview skipped)',
  '已写入并回读：{text}': 'Wrote and read back: {text}',
  '二进制回写一致（{bytes} 字节）': 'Binary round-trip matched ({bytes} bytes)',
  二进制回写不一致: 'Binary round-trip did not match',
  '[目录] {name}': '[Directory] {name}',
  '[文件] {name} · {size} B': '[File] {name} · {size} B',
  '{directory} 目录为空，先写入一个文件试试':
    '{directory} is empty; write a file first',
  '已删除沙箱目录 {directory}': 'Deleted sandbox directory {directory}',
  '缓存沙箱根目录：{uri}': 'Cache sandbox root: {uri}',

  '等待选择页关闭…': 'Waiting for the picker page to close…',
  '页面已关闭，未携带结果': 'The page closed without a result',
  '页面已关闭，结果: {result}': 'The page closed with result: {result}',
  '事件 × {count} · 最后：{event}': 'Events × {count} · Last: {event}',
  '{title}（无触感）': '{title} (no haptics)',
  '{kind} · {label}': '{kind} · {label}',
  点击: 'Tap',
  长按: 'Long Press',
  无触感按钮: 'No-haptics button',
  触感按钮: 'Haptics button',
  未启用系统触感: 'System haptics disabled',
  已启用系统触感: 'System haptics enabled',

  '当前亮度 {percent}%': 'Current brightness: {percent}%',
  '亮度已设为 {percent}%': 'Brightness set to {percent}%',
  已开启屏幕常亮: 'Keep Screen On enabled',
  已关闭屏幕常亮: 'Keep Screen On disabled',
  已切换为深色文字: 'Switched to dark content',
  已切换为浅色文字: 'Switched to light content',

  '{downloaded} · 总大小未知': '{downloaded} · total size unknown',
  '{platform} · {modes}\n断点续传：{resume} · 进程重启恢复：{recovery}':
    '{platform} · {modes}\nByte-range resume: {resume} · Process-restart recovery: {recovery}',
  应用内: 'In-app',
  '刷新失败：{message}': 'Refresh failed: {message}',
  '能力探测失败：{message}': 'Capability detection failed: {message}',
  '下载完成：{file}': 'Download completed: {file}',
  '下载失败：{message}': 'Download failed: {message}',
  未知错误: 'Unknown error',
  请输入下载地址: 'Enter a download URL',
  '请输入 http:// 或 https:// 下载地址': 'Enter an http:// or https:// URL',
  '当前平台不支持 Android 前台下载模式':
    'Android foreground downloads are not supported on this platform',
  '正在申请通知权限并启动 Android 前台任务…':
    'Requesting notification permission and starting an Android foreground task…',
  '正在创建下载任务…': 'Creating a download task…',
  ' · 通知权限 {status}': ' · notification permission {status}',
  '前台任务已启动{notification}；进度已落盘，可切到后台观察。':
    'Foreground task started{notification}; progress is persisted, so you can background the app.',
  '任务已启动且进度已落盘：{file}':
    'Task started with persisted progress: {file}',
  '启动失败：{message}': 'Start failed: {message}',
  '操作失败：{message}': 'Operation failed: {message}',
  '删除失败：{message}': 'Delete failed: {message}',
  任务记录及其缓存文件已删除: 'Deleted the task record and its cached file',
  '任务列表（{count}）': 'Tasks ({count})',
  删除任务和文件: 'Delete Task and File',
  删除任务: 'Delete Task',
  刷新任务列表: 'Refresh Tasks',

  '已输入 {count} 字：{value}': '{count} characters entered: {value}',
  '已输入 {count} 字': '{count} characters entered',
  '已发送：{message}': 'Sent: {message}',
  弹窗已取消: 'Dialog cancelled',
  主要按钮被点击: 'Primary button tapped',
  次要按钮被点击: 'Secondary button tapped',
  警示操作被点击: 'Destructive action tapped',
  对话框已打开: 'Dialog opened',
  对话框已关闭: 'Dialog closed',
  已确认删除: 'Deletion confirmed',
  弹层已打开: 'Sheet opened',
  弹层已关闭: 'Sheet closed',
  'overlay 页面已关闭': 'Overlay page closed',

  '播放中 · {position} / {duration}': 'Playing · {position} / {duration}',
  '双指或双击缩放 · 放大后单指拖动 · 点击空白关闭':
    'Pinch or double-tap to zoom · Drag with one finger when zoomed · Tap outside to close',
  '{label}截图：{width}x{height} · {file}':
    '{label} capture: {width}x{height} · {file}',
  '{label}截图已生成': '{label} capture created',
  '{width}×{height} · 点击全屏查看，支持缩放':
    '{width}×{height} · Tap for a zoomable full-screen view',
  卡片: 'Card',
  视图: 'LynxView',
  页面: 'Page',
  '就绪 · {position} / {duration}': 'Ready · {position} / {duration}',
  '播放错误：{message}': 'Playback error: {message}',
  '无法播放：{message}': 'Unable to play: {message}',
  '选择失败：{message}': 'Selection failed: {message}',
  ' · 打断：{interruption}': ' · interruption: {interruption}',
  '已达时长上限自动停止 · {duration}':
    'Stopped automatically at the duration limit · {duration}',
  '录音错误：{message}': 'Recording error: {message}',
  '无法开始录音：{message}': 'Unable to start recording: {message}',
  '已保存 · {duration} · {size} · m4a': 'Saved · {duration} · {size} · m4a',
  '停止失败：{message}': 'Stop failed: {message}',
  '回放 · {position} / {duration}': 'Playback · {position} / {duration}',
  '回放错误：{message}': 'Playback error: {message}',
  '麦克风权限未授予，无法录音':
    'Microphone permission was not granted; recording is unavailable',
  '录音中 · 0:00': 'Recording · 0:00',
  '已暂停 · 可继续录音': 'Paused · recording can resume',
  录音中: 'Recording',
  '已丢弃，可重新录音': 'Discarded; ready to record again',
  回放中: 'Playing back',
  '加载中 · 0:00 / 0:00': 'Loading · 0:00 / 0:00',
  '→ 打开系统相册选择图片': '→ Opening the system photo picker',
  '· 已取消选择': '· Selection cancelled',
  '→ 截取当前页面作为输入图': '→ Capturing the current page as input',
  '← 输入 {width}×{height} · {type} · {size}':
    '← Input {width}×{height} · {type} · {size}',
  '← 压缩 {width}×{height} · {size}': '← Compressed {width}×{height} · {size}',
  '← 中心裁剪 {width}×{height}': '← Center crop {width}×{height}',
  '← 横拼 {width}×{height}': '← Horizontal composition {width}×{height}',
  '← 竖拼 {width}×{height}': '← Vertical composition {width}×{height}',
  '← 叠加 {width}×{height} · 图层透明度 0.65':
    '← Overlay {width}×{height} · layer opacity 0.65',
  '← EXIF 写入 Software={software} · GPS={gps}':
    '← EXIF write Software={software} · GPS={gps}',
  '← EXIF 定点删除 · GPS {state}': '← Selective EXIF removal · GPS {state}',
  '← EXIF 全量清除 · {count} 个 tag · GPS {state}':
    '← Cleared all EXIF · {count} tags · GPS {state}',
  未读到: 'not found',
  已清除: 'cleared',
  仍存在: 'still present',
  无: 'none',
  '{label}：分享面板已打开…': '{label}: Share sheet opened…',
  '{label}：已交给目标{target}': '{label}: Handed off to target{target}',
  '{label}：已取消': '{label}: Cancelled',
  '{label}：{message}': '{label}: {message}',
  文本: 'Text',
  链接: 'Link',

  '{device}\n系统 {os} · 应用 v{version} ({build})\n密度 {density}x · {locale}{traits}':
    '{device}\nOS {os} · App v{version} ({build})\nDensity {density}x · {locale}{traits}',
  '屏幕 {screen} / 窗口 {window} / LynxView {view}':
    'Screen {screen} / Window {window} / LynxView {view}',
  平板: 'Tablet',
  折叠屏: 'Foldable',
  '电量 {percent}% · {charging}': 'Battery {percent}% · {charging}',
  充电中: 'Charging',
  未充电: 'Not charging',
  '该设备无法读取电量（iOS 模拟器返回空）':
    'Battery level is unavailable (the iOS Simulator returns no value)',
  该设备不支持加速度计: 'This device does not support an accelerometer',
  该设备不支持指南针: 'This device does not support a compass',
  该设备不支持陀螺仪: 'This device does not support a gyroscope',
  该设备不支持磁力计: 'This device does not support a magnetometer',
  该设备不支持气压计: 'This device does not support a barometer',
  '错误：{message}': 'Error: {message}',
  'x {x} · y {y} · z {z} m/s²': 'x {x} · y {y} · z {z} m/s²',
  'x {x} · y {y} · z {z} rad/s': 'x {x} · y {y} · z {z} rad/s',
  'x {x} · y {y} · z {z} µT': 'x {x} · y {y} · z {z} µT',
  '气压 {pressure} hPa': 'Pressure {pressure} hPa',
  '朝向 {heading}° · 精度 ±{accuracy}':
    'Heading {heading}° · accuracy ±{accuracy}',
  '{availability} · 类型 {type}\n{policy} · {reason} · 锁屏凭据{credential}':
    '{availability} · type {type}\n{policy} · {reason} · device credential {credential}',
  已设置: 'configured',
  '等待系统认证弹窗…': 'Waiting for the system authentication prompt…',
  '系统生物认证通过 ✓ · {policy}':
    'System biometric authentication succeeded ✓ · {policy}',
  '未通过：{code}': 'Not authenticated: {code}',
  '正在生成硬件签名密钥…': 'Creating a hardware signing key…',
  '密钥已创建：{key}\n{level} · 公钥 {publicKey}…':
    'Key created: {key}\n{level} · public key {publicKey}…',
  '创建失败：{code}': 'Creation failed: {code}',
  请先生成一把签名密钥: 'Create a signing key first',
  '正在签名本地挑战…': 'Signing the local challenge…',
  '签名成功：{signature}…': 'Signature created: {signature}…',
  '签名失败：{code}': 'Signing failed: {code}',
  当前没有演示密钥: 'There is no demo key',
  演示密钥已删除: 'Demo key deleted',
  '已写入：{value}': 'Wrote: {value}',
  剪贴板为空: 'Clipboard is empty',
  '剪贴板内容：{value}': 'Clipboard: {value}',
  '已触发 {style} 振动': 'Triggered {style} haptics',
  '{style} 振动': '{style} Haptics',
  '等待扫码…': 'Waiting for a scan…',
  '请选择一张图片…': 'Choose an image…',
  已取消选择: 'Selection cancelled',
  '未完成：{code}': 'Not completed: {code}',
};

interface InterpolatedMessage {
  names: string[];
  pattern: RegExp;
  translation: string;
}

function escapePattern(source: string): string {
  return source.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

const interpolatedEnglish: InterpolatedMessage[] = Object.entries(english)
  .filter(([source]) => /\{\w+\}/.test(source))
  // Try the most specific literal frame first so a generic message such as
  // "{kind} · {label}" cannot swallow a richer diagnostic template.
  .sort(
    ([left], [right]) =>
      right.replace(/\{\w+\}/g, '').length -
      left.replace(/\{\w+\}/g, '').length,
  )
  .map(([source, translation]) => {
    const names: string[] = [];
    const parts: string[] = [];
    const placeholder = /\{(\w+)\}/g;
    let cursor = 0;
    let match = placeholder.exec(source);
    while (match !== null) {
      parts.push(escapePattern(source.slice(cursor, match.index)));
      parts.push('([\\s\\S]*?)');
      names.push(match[1] ?? '');
      cursor = match.index + match[0].length;
      match = placeholder.exec(source);
    }
    parts.push(escapePattern(source.slice(cursor)));
    return {
      names,
      pattern: new RegExp(`^${parts.join('')}$`),
      translation,
    };
  });

function translateCapturedValue(source: string): string {
  const exact = english[source];
  if (exact !== undefined) {
    return exact;
  }
  // Lists in the demos retain their source values for native callbacks, then
  // arrive here as one display string. Translate each item without changing
  // the underlying value used by the API call.
  if (/[、]| \/ | · |[（）]/.test(source)) {
    let changed = false;
    const translated = source
      .split(/(、| \/ | · |（|）)/)
      .map((item) => {
        const exactItem = english[item];
        if (exactItem !== undefined) {
          changed = true;
          return exactItem;
        }
        if (item === '、') {
          changed = true;
          return ', ';
        }
        if (item === '（') {
          changed = true;
          return '(';
        }
        if (item === '）') {
          changed = true;
          return ')';
        }
        return item;
      })
      .join('');
    if (changed) {
      return translated;
    }
  }
  const interpolated = translateInterpolated(source);
  if (interpolated !== undefined && interpolated !== source) {
    return interpolated;
  }
  return source;
}

function translateInterpolated(source: string): string | undefined {
  for (const message of interpolatedEnglish) {
    const match = message.pattern.exec(source);
    if (match === null) {
      continue;
    }
    const values: MessageValues = {};
    message.names.forEach((name, index) => {
      values[name] = translateCapturedValue(match[index + 1] ?? '');
    });
    return formatMessage(message.translation, values);
  }
  return undefined;
}

function formatMessage(template: string, values?: MessageValues): string {
  if (values === undefined) {
    return template;
  }
  return template.replace(/\{(\w+)\}/g, (match, key: string) =>
    values[key] === undefined ? match : String(values[key]),
  );
}

export function setAppLocale(locale: AppLocale): void {
  currentLocale = locale;
}

export function t(source: string, values?: MessageValues): string {
  const template =
    currentLocale === 'en'
      ? (english[source] ?? translateInterpolated(source) ?? source)
      : source;
  return formatMessage(template, values);
}
