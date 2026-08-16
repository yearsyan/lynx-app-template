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

当前三端客户端只对 `main` 自动检查 OTA；其他路由 bundle 使用随 App 发布的内置资源。若要独立热更新次级 bundle，需要把缓存和检查流程扩展为按 bundle 名索引。

## 客户端校验

1. Release 只接受 HTTPS manifest 和 bundle；
2. `schemaVersion` 必须为 `1`；
3. `engineVersion` 必须与宿主支持的 bundle 版本契约完全一致，且不能高于宿主 SDK；
4. 下载字节数必须等于 `size`；
5. 文件 SHA-256 必须等于 manifest；
6. 校验后先写临时文件，再替换正式缓存；
7. 任意步骤失败都继续使用上次有效缓存或安装包内资源。

## 本地缓存元数据

OTA 校验通过后，三个宿主把同一份 JSON 元数据与 bundle 一起写入应用私有目录（文件名 `main.metadata.json`）：

```json
{
  "engineVersion": "3.9",
  "version": "1.0.0",
  "sha256": "<64 lowercase hex characters>"
}
```

启动时宿主重新计算缓存 bundle 的 SHA-256 并与 `sha256` 比对；`engineVersion` 不匹配或校验失败都会回退到安装包内资源。

manifest 中的 `engineVersion` 与 `sdkVersion` 来源于根目录 `package.json` 的 `lynx` 字段，由 `pnpm build:lynx` 读取写入。三个宿主与各 bundle 的 `lynx.config.ts` 各自硬编码同一 `engineVersion`，`pnpm native:check` 会校验这些副本与 `package.json` 一致。

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
