import { useCallback, useState } from '@lynx-js/react';
import { fileSystem } from '@lynx-template/autolink-file-system';
import { kv, secureStorage } from '@lynx-template/autolink-storage';

import {
  ApiName,
  DemoButton,
  DemoCard,
  ResultLine,
} from '../components/Demo.js';

const KV_KEY = 'demo.kv';
const SANDBOX_DIR = 'demo';

export function KvPage() {
  const [result, setResult] = useState<string | null>(null);

  const save = useCallback(() => {
    'background only';
    const value = `kv-${Date.now()}`;
    kv.setString(KV_KEY, value)
      .then(() => setResult(`已写入 ${KV_KEY} = ${value}`))
      .catch((error: Error) => setResult(error.message));
  }, []);

  const read = useCallback(() => {
    'background only';
    kv.getString(KV_KEY)
      .then((value) =>
        setResult(
          value === null ? 'MMKV 中暂无数据' : `读到 ${KV_KEY} = ${value}`,
        ),
      )
      .catch((error: Error) => setResult(error.message));
  }, []);

  const remove = useCallback(() => {
    'background only';
    kv.remove(KV_KEY)
      .then(() => setResult(`已删除 ${KV_KEY}`))
      .catch((error: Error) => setResult(error.message));
  }, []);

  return (
    <view>
      <ApiName name="kv.setString" />
      <DemoCard
        title="MMKV 键值存储"
        desc="原生 MMKV 高性能键值存储，适合缓存与小数据持久化，跨启动保留。"
      >
        <DemoButton label="写入" primary onTap={save} />
        <DemoButton label="读取" onTap={read} />
        <DemoButton label="删除" onTap={remove} />
        <ResultLine text={result} placeholder="写入 → 读取 → 删除 完整闭环" />
      </DemoCard>
    </view>
  );
}

const SECRET_KEY = 'demo.secret';

export function SecureStoragePage() {
  const [result, setResult] = useState<string | null>(null);

  const save = useCallback(() => {
    'background only';
    const value = `token-${Date.now()}`;
    secureStorage
      .setString(SECRET_KEY, value)
      .then(() => setResult(`已加密写入 ${SECRET_KEY} = ${value}`))
      .catch((error: Error) => setResult(error.message));
  }, []);

  const read = useCallback(() => {
    'background only';
    secureStorage
      .getString(SECRET_KEY)
      .then((value) =>
        setResult(
          value === null
            ? '安全存储中暂无数据'
            : `读到 ${SECRET_KEY} = ${value}`,
        ),
      )
      .catch((error: Error) => setResult(error.message));
  }, []);

  const remove = useCallback(() => {
    'background only';
    secureStorage
      .remove(SECRET_KEY)
      .then(() => setResult(`已删除 ${SECRET_KEY}`))
      .catch((error: Error) => setResult(error.message));
  }, []);

  return (
    <view>
      <ApiName name="secureStorage.setString" />
      <DemoCard
        title="安全存储"
        desc="Android Keystore 加密 / iOS Keychain / 鸿蒙 HUKS，适合 Token 等短小机密（最长 64KB）。"
      >
        <DemoButton label="加密写入" primary onTap={save} />
        <DemoButton label="读取" onTap={read} />
        <DemoButton label="删除" onTap={remove} />
        <ResultLine text={result} placeholder="加密写入后可读取验证" />
      </DemoCard>
    </view>
  );
}

export function FileSystemPage() {
  const [result, setResult] = useState<string | null>(null);
  const [sandboxResult, setSandboxResult] = useState<string | null>(null);

  const pickAndRead = useCallback(() => {
    'background only';
    fileSystem
      .pick()
      .then(async (uris) => {
        const uri = uris[0];
        if (uri === undefined) {
          setResult('已取消选择');
          return;
        }
        const info = await fileSystem.stat(uri);
        const size =
          info.size === null
            ? '未知大小'
            : `${(info.size / 1024).toFixed(1)} KB`;
        const header = `${info.name} · ${size} · ${info.mimeType ?? '未知类型'}`;
        try {
          const text = await fileSystem.readText(uri, { maxBytes: 4096 });
          const snippet = text.replace(/\s+/g, ' ').slice(0, 200);
          setResult(
            `${header}\n文本预览：${snippet}${text.length > 200 ? ' …' : ''}`,
          );
        } catch {
          setResult(`${header}\n（二进制文件，跳过文本预览）`);
        }
      })
      .catch((error: Error) => setResult(error.message));
  }, []);

  const writeSandboxText = useCallback(() => {
    'background only';
    const contents = `lynx-demo-${Date.now()}`;
    fileSystem
      .writeText(`${SANDBOX_DIR}/hello.txt`, contents, { append: true })
      .then(async (uri) => {
        const text = await fileSystem.readText(uri);
        setSandboxResult(`已写入并回读：${text}`);
      })
      .catch((error: Error) => setSandboxResult(error.message));
  }, []);

  const writeSandboxBinary = useCallback(() => {
    'background only';
    const bytes = new Uint8Array(256);
    for (let index = 0; index < bytes.length; index += 1) {
      bytes[index] = index;
    }
    fileSystem
      .writeArrayBuffer(`${SANDBOX_DIR}/blob.bin`, bytes.buffer)
      .then(async () => {
        const readBack = await fileSystem.readArrayBuffer(
          `${SANDBOX_DIR}/blob.bin`,
        );
        const roundtrip = new Uint8Array(readBack);
        setSandboxResult(
          roundtrip.length === bytes.length && roundtrip[15] === 15
            ? `二进制回写一致（${roundtrip.length} 字节）`
            : '二进制回写不一致',
        );
      })
      .catch((error: Error) => setSandboxResult(error.message));
  }, []);

  const listSandboxDir = useCallback(() => {
    'background only';
    fileSystem
      .listDir(SANDBOX_DIR)
      .then((entries) => {
        const lines = entries.map((entry) =>
          entry.isDirectory
            ? `[目录] ${entry.name}`
            : `[文件] ${entry.name} · ${entry.size ?? '?'} B`,
        );
        setSandboxResult(
          lines.length > 0
            ? lines.join('\n')
            : `${SANDBOX_DIR} 目录为空，先写入一个文件试试`,
        );
      })
      .catch((error: Error) => setSandboxResult(error.message));
  }, []);

  const removeSandboxDir = useCallback(() => {
    'background only';
    fileSystem
      .delete(SANDBOX_DIR)
      .then(() => setSandboxResult(`已删除沙箱目录 ${SANDBOX_DIR}`))
      .catch((error: Error) => setSandboxResult(error.message));
  }, []);

  const showCacheDir = useCallback(() => {
    'background only';
    fileSystem
      .cacheDir()
      .then((uri) => setSandboxResult(`缓存沙箱根目录：${uri}`))
      .catch((error: Error) => setSandboxResult(error.message));
  }, []);

  return (
    <view>
      <ApiName name="fileSystem.pick" />
      <DemoCard
        title="文件系统"
        desc="系统文件选择器选取任意文件，stat 读取元数据，readText 读取前 4KB 文本内容。"
      >
        <DemoButton label="选择文件并读取" primary onTap={pickAndRead} />
        <ResultLine text={result} placeholder="选中文件的元数据与文本预览" />
      </DemoCard>
      <ApiName name="fileSystem.writeText / writeArrayBuffer / listDir / delete" />
      <DemoCard
        title="缓存沙箱读写"
        desc="在应用缓存沙箱内写入文本与二进制文件、列目录、删除目录；路径只能落在沙箱内。"
      >
        <DemoButton label="写入文本" primary onTap={writeSandboxText} />
        <DemoButton label="写入二进制并回读" onTap={writeSandboxBinary} />
        <DemoButton label="列目录" onTap={listSandboxDir} />
        <DemoButton label="删除目录" onTap={removeSandboxDir} />
        <DemoButton label="查看沙箱根目录" onTap={showCacheDir} />
        <ResultLine
          text={sandboxResult}
          placeholder="写入 / 列出 / 删除缓存沙箱文件"
        />
      </DemoCard>
    </view>
  );
}
