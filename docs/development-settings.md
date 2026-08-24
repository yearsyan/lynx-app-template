# Debug 开发配置

iOS、Android 和 HarmonyOS 的 Debug App 都在主页面右上角提供原生 `DEV` 入口。入口支持拖动调整位置，松手后位置会保存在当前设备；轻点（未产生拖动）仍打开配置页。配置保存在当前设备，不需要修改或重新编译原生工程；Release 不显示入口，也不读取这些值。

## 字段

`Bundle servers` 用于决定指定 ID 的 bundle 从哪里加载。配置页以列表展示当前映射，每项包含 bundle ID 和服务 URL，并提供编辑、删除和新增操作。

新增时可以从下拉菜单选择当前设备已经加载过的 bundle；宿主会记录主 bundle 和通过原生路由打开过的 bundle ID。也可以直接手动输入尚未加载的 bundle ID，因此不要求先打开目标页面。

bundle ID 只允许小写字母、数字和连字符，且不能重复。URL 必须是 `http://` 或 `https://`：

- 服务根 URL 会自动追加 `/<bundle-id>.lynx.bundle`；
- 已以 `.lynx.bundle` 结尾的完整 URL 保持不变；
- 保存前会统一校验并规范化，错误会直接显示在配置页；
- 保存和清空都会关闭配置页并重新加载主 bundle。

旧版本保存的 `bundle-id=URL` 多行配置会继续读取，并在新列表中逐项展示。

## 加载优先级

对任意 bundle，Debug 设备映射优先于工程中的旧式固定开发 URL。`main` 没有设备映射时继续依次使用旧式 Debug URL、已校验的热更新缓存和安装包内资源；其他 bundle 没有设备映射时使用安装包内资源。主 bundle 使用开发映射时会暂停热更新检查，避免开发内容被切换掉。

## ADB 设备文件映射（Android）

除了 App 内的 DEV 配置页，Android Debug 包还会读取固定路径的设备文件
`/data/local/tmp/lynx_dev_bundles.txt`。它与 DEV 面板共用同一种逐行格式
（`bundle-id=server-url`，支持 `#` 注释与空行；根 URL 同样自动补
`/<bundle-id>.lynx.bundle`），但面向的是脚本与自动化：无需重编译、无需打开
App，一条 `adb push` 即可改向，再次打开页面时生效：

```bash
printf 'main=http://192.168.9.138:3000\nprofile=http://192.168.9.138:3001\n' \
  | adb shell 'cat > /data/local/tmp/lynx_dev_bundles.txt'
# 恢复内置加载：adb shell rm /data/local/tmp/lynx_dev_bundles.txt
```

可行性边界：`/data/local/tmp` 对应用是「可穿越、不可列举」，因此文件名必须固定；
adb 推入的文件默认全局可读，App 用应用内 `File` API 直读即可，不需要任何权限。
个别厂商 / 版本的 SELinux 策略可能拒绝应用读取该目录，此时整个文件按「无映射」
静默忽略——它永远不会阻塞启动。生效优先级：DEV 面板映射 > 设备文件映射 >
旧式 Debug URL（`LYNX_DEV_BUNDLE_URL`）> 热更新缓存 > 安装包内资源；主 bundle
命中设备文件映射时同样暂停热更新检查。该文件仅 Debug 读取，Release 看不到入口。

## 加载失败回退

开发服务器不可达、bundle 拉取或解析失败（Lynx bundle 加载类错误）时，三端都会自动回退到
安装包内的 bundle 重新渲染一次，避免出现白屏；回退只执行一次，内置 bundle 自身失败时错误
仍然可见。JS 运行时错误不触发回退，保证开发中的错误不会被内置 bundle 掩盖。

## Release 隔离

- Android：配置 Activity 和入口只位于 `src/debug`；Release 使用 `src/release` 空入口，R8 会裁掉共享读取代码。
- iOS：配置页和入口由 `#if DEBUG` 编译；共享读取逻辑在非 Debug 分支固定返回空值。
- HarmonyOS：配置页、存储与 DevTool 注册的默认实现是 `entry/src/main` 下的同名空壳，`entry@debug` target 通过扩展源码根 `src/debug` 在同路径覆盖为真实实现；Hvigor 仅在 debug build mode 注入 DevTool 依赖，同时该 target 用 `runtimeOnly` 保留动态加载的实现。Release 不编译配置文案、MMKV key、URL 解析或 DevTool service，也不打包 `liblynxdevtool.so` 与 DevTool 资源（可通过解包 release HAP 检索验证）。

三端 Release 仍只允许 HTTPS 网络策略；本地明文 HTTP 只用于 Debug 开发。
