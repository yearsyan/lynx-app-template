import { fileSystem, kv, secureStorage } from '@lynx-app/native-bridge';
import { useCallback, useState } from '@lynx-js/react';

import {
  ApiName,
  DemoButton,
  DemoCard,
  ResultLine,
} from '../components/Demo.js';

const KV_KEY = 'demo.kv';

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
    </view>
  );
}
