import { router, WebSocketConnection } from '@lynx-app/native-bridge';
import { useCallback, useEffect, useRef, useState } from '@lynx-js/react';

import {
  ApiName,
  DemoButton,
  DemoCard,
  ResultLine,
} from '../components/Demo.js';

interface FetchTarget {
  label: string;
  url: string;
}

const TARGETS: FetchTarget[] = [
  {
    label: 'GET postman-echo.com',
    url: 'https://postman-echo.com/get?source=lynx',
  },
  { label: 'GET baidu.com', url: 'https://www.baidu.com' },
];

export function FetchPage() {
  const [result, setResult] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  const run = useCallback((target: FetchTarget) => {
    'background only';
    setLoading(true);
    setResult(`正在请求 ${target.url} …`);
    fetch(target.url, { headers: { Accept: 'application/json, text/html' } })
      .then(async (response) => {
        const body = await response.text();
        const snippet = body.replace(/\s+/g, ' ').slice(0, 240);
        setResult(
          `HTTP ${response.status} · ${body.length} 字节\n${snippet}${body.length > 240 ? ' …' : ''}`,
        );
      })
      .catch((error: Error) => setResult(`请求失败：${error.message}`))
      .finally(() => setLoading(false));
  }, []);

  return (
    <view>
      <ApiName name="fetch" />
      <DemoCard
        title="发起请求"
        desc="Bundle 内直接使用标准 fetch；三端宿主分别用 OkHttp / URLSession / Network Kit 传输，Debug 允许 http，Release 仅 https。"
      >
        {TARGETS.map((target) => (
          <DemoButton
            key={target.url}
            label={target.label}
            primary={target === TARGETS[0]}
            disabled={loading}
            onTap={() => run(target)}
          />
        ))}
        <ResultLine text={result} placeholder="选择一个目标发起 GET 请求" />
      </DemoCard>
    </view>
  );
}

const ECHO_URL = 'wss://ws.postman-echo.com/raw';
const MAX_LOG_LINES = 12;

export function WebSocketPage() {
  const [lines, setLines] = useState<string[]>([]);
  const [connected, setConnected] = useState(false);
  const socketRef = useRef<WebSocketConnection | null>(null);

  const append = useCallback((line: string) => {
    'background only';
    setLines((current) => [...current.slice(-MAX_LOG_LINES + 1), line]);
  }, []);

  const teardown = useCallback(() => {
    'background only';
    const socket = socketRef.current;
    socketRef.current = null;
    setConnected(false);
    if (socket !== null && socket.readyState === WebSocketConnection.OPEN) {
      socket.close().catch(() => {});
    }
  }, []);

  useEffect(() => {
    'background only';
    return () => {
      'background only';
      const socket = socketRef.current;
      socketRef.current = null;
      socket?.close().catch(() => {});
    };
  }, []);

  const connect = useCallback(() => {
    'background only';
    if (socketRef.current !== null) return;
    append(`→ 连接 ${ECHO_URL}`);
    const socket = new WebSocketConnection({ url: ECHO_URL });
    socketRef.current = socket;
    socket.addEventListener('open', () => {
      'background only';
      setConnected(true);
      append('← 已连接（echo 服务器会原样回发）');
    });
    socket.addEventListener('message', (event) => {
      'background only';
      append(`← 收到：${event.data}`);
    });
    socket.addEventListener('error', (event) => {
      'background only';
      append(`! 错误：${event.message}`);
    });
    socket.addEventListener('close', (event) => {
      'background only';
      setConnected(false);
      socketRef.current = null;
      append(
        `← 已关闭 code=${event.code}${event.wasClean ? '（正常）' : '（异常）'}`,
      );
    });
    socket.opened.catch((error: Error) => {
      'background only';
      socketRef.current = null;
      setConnected(false);
      append(`! 连接失败：${error.message}`);
    });
  }, [append]);

  const send = useCallback(() => {
    'background only';
    const socket = socketRef.current;
    if (socket === null || socket.readyState !== WebSocketConnection.OPEN) {
      append('! 尚未连接');
      return;
    }
    const payload = `hello lynx @ ${new Date().toLocaleTimeString()}`;
    socket
      .send(payload)
      .then(() => append(`→ 发送：${payload}`))
      .catch((error: Error) => append(`! 发送失败：${error.message}`));
  }, [append]);

  return (
    <view>
      <ApiName name="WebSocketConnection" />
      <DemoCard
        title="WebSocket"
        desc="应用自有的全双工长连接（不依赖 DevTool 调试通道）；事件通过 GlobalEventEmitter 分发。"
      >
        <DemoButton
          label={connected ? '已连接' : '连接 echo 服务器'}
          primary
          disabled={connected}
          onTap={connect}
        />
        <DemoButton label="发送一条消息" disabled={!connected} onTap={send} />
        <DemoButton label="断开连接" disabled={!connected} onTap={teardown} />
        <view className="LogBox">
          {lines.length === 0 ? (
            <text className="LogBox__empty">事件日志展示在这里</text>
          ) : (
            lines.map((line, index) => (
              <text key={index} className="LogBox__line">
                {line}
              </text>
            ))
          )}
        </view>
      </DemoCard>
    </view>
  );
}

export function OpenUrlPage() {
  const [result, setResult] = useState<string | null>(null);

  const open = useCallback((url: string) => {
    'background only';
    router
      .openURL(url)
      .then(() => setResult(`已交给系统处理：${url}`))
      .catch((error: Error) => setResult(`打开失败：${error.message}`));
  }, []);

  return (
    <view>
      <ApiName name="router.openURL" />
      <DemoCard
        title="打开链接"
        desc="把 URL 交给系统路由解析：https 走浏览器，自定义 scheme 唤起注册了该 scheme 的应用。"
      >
        <DemoButton
          label="打开 https://www.lynxjs.org"
          primary
          onTap={() => open('https://www.lynxjs.org')}
        />
        <DemoButton
          label="打开 lynxapp://main"
          onTap={() => open('lynxapp://main')}
        />
        <ResultLine text={result} placeholder="选择一个链接交给系统打开" />
      </DemoCard>
    </view>
  );
}
