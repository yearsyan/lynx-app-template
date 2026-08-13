# Debug 开发配置

iOS、Android 和 HarmonyOS 的 Debug App 都在主页面右上角提供原生 `DEV` 入口。配置保存在当前设备，不需要修改或重新编译原生工程；Release 不显示入口，也不读取这些值。

## 字段

`API Server` 是业务接口根地址。保存后，宿主会在加载每个 Lynx bundle 时通过 `nativeEnvironment.apiServer` 注入；字段结构、默认值和更新行为统一由 [Native Environment 数据契约](native-environment.md) 定义。

`Bundle servers` 用于决定指定 ID 的 bundle 从哪里加载，每行一条：

```text
# 空行和注释会被忽略
main=http://192.168.1.10:3000
native-capabilities=http://192.168.1.10:3001
profile=http://192.168.1.10:3002/profile.lynx.bundle
```

bundle ID 只允许小写字母、数字和连字符，且不能重复。URL 必须是 `http://` 或 `https://`：

- 服务根 URL 会自动追加 `/<bundle-id>.lynx.bundle`；
- 已以 `.lynx.bundle` 结尾的完整 URL 保持不变；
- 保存前会统一校验并规范化，错误会直接显示在配置页；
- 保存和清空都会关闭配置页并重新加载主 bundle。

## 加载优先级

对任意 bundle，Debug 设备映射优先于工程中的旧式固定开发 URL。`main` 没有设备映射时继续依次使用旧式 Debug URL、已校验的热更新缓存和安装包内资源；其他 bundle 没有设备映射时使用安装包内资源。主 bundle 使用开发映射时会暂停热更新检查，避免开发内容被切换掉。

业务 `API Server` 与 bundle 开发服务器相互独立：前者只注入 JS，后者只决定 `.lynx.bundle` 的加载地址。

## Release 隔离

- Android：配置 Activity 和入口只位于 `src/debug`；Release 使用 `src/release` 空入口，R8 会裁掉共享读取代码。
- iOS：配置页和入口由 `#if DEBUG` 编译；共享读取逻辑在非 Debug 分支固定返回空值。
- HarmonyOS：`entry@debug` 与 `entry@release` 使用差异化 source root；Release 只编译同名空实现，不包含配置文案、MMKV key 或 URL 解析逻辑。

三端 Release 仍只允许 HTTPS 网络策略；本地明文 HTTP 只用于 Debug 开发。
