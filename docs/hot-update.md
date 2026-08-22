# Lynx 热更新协议

## Manifest v1

`pnpm build:lynx` 生成如下结构：

```json
{
  "schemaVersion": 1,
  "engineVersion": "3.9",
  "sdkVersion": "4.0.0",
  "channel": "production",
  "generatedAt": "2026-08-12T00:00:00.000Z",
  "bundles": [
    {
      "name": "main",
      "version": "1.0.0",
      "url": "main.lynx.bundle",
      "sha256": "<64 lowercase hex characters>",
      "size": 123456
    }
  ]
}
```

`url` 可以是 HTTPS 绝对地址，也可以相对 manifest 所在目录。客户端只选择与请求名称匹配的条目。

Android 宿主解析 manifest 的全部条目并按 bundle 名索引缓存：`main` 在启动时自动检查，其他 bundle 在 Navigation 打开路由前按内存中的 manifest 对比缓存（有更新时先在 loading 遮罩下下载再进页）。iOS/Harmony 目前只对 `main` 自动检查；次级 bundle 在这两端使用随 App 发布的内置资源。

## 客户端校验

1. Release 只接受 HTTPS manifest 和 bundle；
2. `schemaVersion` 必须为 `1`；
3. `engineVersion` 必须与宿主支持的 bundle 版本契约完全一致，且不能高于宿主 SDK；
4. 下载字节数必须等于 `size`；
5. 文件 SHA-256 必须等于 manifest；
6. 校验后先写临时文件，再替换正式缓存；
7. 任意步骤失败都继续使用上次有效缓存或安装包内资源。

Android 宿主的检查入口有两处：`LynxTemplateApplication` 启动时预取 manifest
（不阻塞进程启动），根页面首帧渲染完成后对比 `main` 缓存，有更新则在
loading 遮罩下下载并重建 Activity 使新缓存生效；`AppRouteHandler` 打开任意
bundle 路由前也会做同样的对比与下载。开发服务器覆盖生效时（debug 构建或
DevelopmentSettings 配置）以上检查全部跳过。

## 本地缓存元数据

OTA 校验通过后，三个宿主把同一份 JSON 元数据与 bundle 一起写入应用私有目录（文件名 `main.metadata.json`）：

```json
{
  "engineVersion": "3.9",
  "version": "1.0.0",
  "sha256": "<64 lowercase hex characters>"
}
```

启动时宿主重新计算缓存 bundle 的 SHA-256 并与 `sha256` 比对；`engineVersion` 不匹配或校验失败都会回退到安装包内资源。运行期拉取或解析缓存 bundle 失败时同样会回退到内置 bundle 重新渲染一次，见 [development-settings.md](development-settings.md) 的「加载失败回退」。

manifest 中的 `engineVersion` 与 `sdkVersion` 来源于根目录 `package.json` 的 `lynx` 字段，由 `pnpm native:sync` 读取写入。三个宿主的 `engineVersion` 常量由 `pnpm native:apply` 直接写入，`pnpm native:check` 校验一致性；bundle 构建使用 `pluginReactLynx()` 的默认兼容目标。

## 发布建议

- bundle 文件使用不可变缓存头；manifest 使用短缓存或 no-cache；
- 先上传 bundle，最后上传 manifest，避免客户端看到尚未存在的文件；
- 灰度环境通过不同 manifest URL 或 `channel` 分流；
- CDN 保留最近几个版本，以便快速回滚 manifest；
- 监控 manifest 请求、校验失败、Lynx fatal error 和首屏成功率。

## 安全边界

本模板实现 HTTPS、大小和 SHA-256 完整性校验。它不能在 CDN、DNS 或发布账号失守时证明发布者身份。生产环境应增加：

- 对 canonical manifest 内容做 Ed25519/ECDSA 离线签名；
- 客户端内置公钥并在解析条目前验证签名；
- 防回滚版本计数或发布时间窗口；
- 服务端发布审批、审计日志和紧急吊销能力。

签名字段可在保持 `schemaVersion: 1` 的情况下作为可选顶层字段试验；若改变 canonicalization 或验证语义，应升级 schema 版本并先发宿主支持。
