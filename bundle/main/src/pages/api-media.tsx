import { useCallback, useEffect, useRef, useState } from '@lynx-js/react';

import '@lynx-template/autolink-webview-bridge';

import { useInitData } from '@lynx-js/react';
import type { TouchEvent as LynxTouchEvent } from '@lynx-js/types';
import { albumUtils } from '@lynx-template/autolink-album-utils';
import type {
  AudioPlayerHandle,
  AudioPlayerStateEvent,
} from '@lynx-template/autolink-audio-player';
import { audioPlayer } from '@lynx-template/autolink-audio-player';
import { readSafeAreaInsets } from '@lynx-template/autolink-device-info';
import { fileSystem } from '@lynx-template/autolink-file-system';
import { screenshot } from '@lynx-template/autolink-screenshot';

import {
  ApiName,
  DemoButton,
  DemoCard,
  ResultLine,
} from '../components/Demo.js';

// `idSelector` is a standard Lynx element attribute that the native
// screenshot lookups resolve against; react-lynx's prop typings do not
// declare it yet.
const screenshotCardSelector: Record<string, string> = {
  idSelector: 'screenshot-card',
};

interface ShotResult {
  label: string;
  uri: string;
  width: number;
  height: number;
}

function summarizeShot(
  label: string,
  result: { uri: string; width: number; height: number },
): string {
  'background only';
  return `${label}截图：${Math.round(result.width)}x${Math.round(result.height)} · ${
    result.uri.split('/').pop() ?? result.uri
  }`;
}

const VIEWER_MIN_SCALE = 0.5;
const VIEWER_MAX_SCALE = 6;
const VIEWER_DOUBLE_TAP_SCALE = 2.5;
const VIEWER_DOUBLE_TAP_INTERVAL = 300;

/** Fullscreen black viewer with pinch / double-tap zoom and pan. */
function ScreenshotViewer(props: { shot: ShotResult; onClose: () => void }) {
  const { shot } = props;
  const initData = useInitData();
  const insets = readSafeAreaInsets(initData);
  const topInset = insets.top > 0 ? insets.top : 48;
  const bottomInset = insets.bottom > 0 ? insets.bottom : 0;

  const viewportWidth = SystemInfo.pixelWidth / SystemInfo.pixelRatio;
  const viewportHeight = SystemInfo.pixelHeight / SystemInfo.pixelRatio;
  const fit = Math.min(
    viewportWidth / shot.width,
    viewportHeight / shot.height,
    1,
  );
  const baseWidth = Math.max(1, Math.round(shot.width * fit));
  const baseHeight = Math.max(1, Math.round(shot.height * fit));

  const [scale, setScale] = useState(1);
  const [translateX, setTranslateX] = useState(0);
  const [translateY, setTranslateY] = useState(0);
  // Gesture baselines and the latest transform are kept in refs so the
  // high-frequency touchmove handler never reads stale state.
  const scaleRef = useRef(1);
  const translateRef = useRef({ x: 0, y: 0 });
  const pinchBase = useRef<{ dist: number; scale: number } | null>(null);
  const panBase = useRef<{
    x: number;
    y: number;
    tx: number;
    ty: number;
  } | null>(null);
  const lastTapAt = useRef(0);

  const applyTransform = useCallback(
    (nextScale: number, tx: number, ty: number) => {
      'background only';
      const clamped = Math.min(
        VIEWER_MAX_SCALE,
        Math.max(VIEWER_MIN_SCALE, nextScale),
      );
      scaleRef.current = clamped;
      translateRef.current = { x: tx, y: ty };
      setScale(clamped);
      setTranslateX(tx);
      setTranslateY(ty);
    },
    [],
  );

  const clampPan = useCallback(
    (x: number, y: number, s: number) => {
      'background only';
      const limitX = (baseWidth * s - viewportWidth) / 2;
      const limitY = (baseHeight * s - viewportHeight) / 2;
      const clampAxis = (value: number, limit: number) =>
        limit > 0 ? Math.min(limit, Math.max(-limit, value)) : 0;
      return { x: clampAxis(x, limitX), y: clampAxis(y, limitY) };
    },
    [baseWidth, baseHeight, viewportWidth, viewportHeight],
  );

  const onTouchStart = useCallback((event: LynxTouchEvent) => {
    'background only';
    const [first, second] = event.touches;
    if (first !== undefined && second !== undefined) {
      pinchBase.current = {
        dist: Math.hypot(
          first.clientX - second.clientX,
          first.clientY - second.clientY,
        ),
        scale: scaleRef.current,
      };
      panBase.current = null;
    } else if (first !== undefined) {
      panBase.current = {
        x: first.clientX,
        y: first.clientY,
        tx: translateRef.current.x,
        ty: translateRef.current.y,
      };
    }
  }, []);

  const onTouchMove = useCallback(
    (event: LynxTouchEvent) => {
      'background only';
      const [first, second] = event.touches;
      if (first !== undefined && second !== undefined && pinchBase.current) {
        const dist = Math.hypot(
          first.clientX - second.clientX,
          first.clientY - second.clientY,
        );
        const next = pinchBase.current.scale * (dist / pinchBase.current.dist);
        applyTransform(next, translateRef.current.x, translateRef.current.y);
      } else if (
        first !== undefined &&
        event.touches.length === 1 &&
        panBase.current &&
        scaleRef.current > 1
      ) {
        const { x, y } = clampPan(
          panBase.current.tx + first.clientX - panBase.current.x,
          panBase.current.ty + first.clientY - panBase.current.y,
          scaleRef.current,
        );
        applyTransform(scaleRef.current, x, y);
      }
    },
    [applyTransform, clampPan],
  );

  const onTouchEnd = useCallback(
    (event: LynxTouchEvent) => {
      'background only';
      const [first] = event.touches;
      if (event.touches.length === 1 && first !== undefined) {
        pinchBase.current = null;
        panBase.current = {
          x: first.clientX,
          y: first.clientY,
          tx: translateRef.current.x,
          ty: translateRef.current.y,
        };
        return;
      }
      if (event.touches.length === 0) {
        pinchBase.current = null;
        panBase.current = null;
        if (scaleRef.current < 1) {
          applyTransform(1, 0, 0);
        }
      }
    },
    [applyTransform],
  );

  const onImageTap = useCallback(() => {
    'background only';
    const now = Date.now();
    if (now - lastTapAt.current < VIEWER_DOUBLE_TAP_INTERVAL) {
      lastTapAt.current = 0;
      if (scaleRef.current > 1.01) {
        applyTransform(1, 0, 0);
      } else {
        applyTransform(VIEWER_DOUBLE_TAP_SCALE, 0, 0);
      }
    } else {
      lastTapAt.current = now;
    }
  }, [applyTransform]);

  return (
    <view className="ShotViewer" bindtap={props.onClose}>
      <view
        className="ShotViewer__stage"
        catchtouchstart={onTouchStart}
        catchtouchmove={onTouchMove}
        catchtouchend={onTouchEnd}
        catchtouchcancel={onTouchEnd}
      >
        <view
          className="ShotViewer__figure"
          style={{
            width: `${baseWidth}px`,
            height: `${baseHeight}px`,
            transform: `translate(${translateX}px, ${translateY}px) scale(${scale})`,
          }}
          catchtap={onImageTap}
        >
          <image
            className="ShotViewer__image"
            src={shot.uri}
            mode="aspectFit"
          />
        </view>
      </view>
      <view
        className="ShotViewer__close"
        style={{ top: `${topInset + 8}px` }}
        catchtap={props.onClose}
      >
        <text className="ShotViewer__closeIcon">✕</text>
      </view>
      <text
        className="ShotViewer__hint"
        style={{ bottom: `${bottomInset + 16}px` }}
      >
        双指或双击缩放 · 放大后单指拖动 · 点击空白关闭
      </text>
    </view>
  );
}

export function ScreenshotPage() {
  const [result, setResult] = useState<string | null>(null);
  const [lastShot, setLastShot] = useState<ShotResult | null>(null);
  const [viewerOpen, setViewerOpen] = useState(false);

  const capture = useCallback(
    (
      label: string,
      call: () => Promise<{ uri: string; width: number; height: number }>,
    ) => {
      'background only';
      call()
        .then((shot) => {
          setResult(summarizeShot(label, shot));
          setLastShot({ label, ...shot });
          setViewerOpen(false);
        })
        .catch((error: Error) => setResult(error.message));
    },
    [],
  );

  return (
    <view>
      <ApiName name="screenshot.capture" />
      <DemoCard
        title="截图"
        desc="把指定卡片、整个 LynxView 或原生页面截为 PNG/JPEG，写入应用缓存目录。"
      >
        <view {...screenshotCardSelector} className="ShotTarget">
          <text className="ShotTarget__text">我是被截取的卡片区域</text>
        </view>
        <DemoButton
          label="截取上方卡片"
          onTap={() =>
            capture('卡片', () =>
              screenshot.capture({
                idSelector: 'screenshot-card',
                format: 'jpeg',
                quality: 90,
                fileName: 'demo-card',
              }),
            )
          }
        />
        <DemoButton
          label="截取整个 LynxView"
          onTap={() =>
            capture('视图', () => screenshot.capture({ format: 'png' }))
          }
        />
        <DemoButton
          label="截取原生页面"
          primary
          onTap={() =>
            capture('页面', () => screenshot.capturePage({ format: 'png' }))
          }
        />
        <ResultLine
          text={result}
          placeholder="截图结果（尺寸与文件）展示在这里"
        />
        {lastShot ? (
          <view className="ShotEntry" bindtap={() => setViewerOpen(true)}>
            <image
              className="ShotEntry__thumb"
              src={lastShot.uri}
              mode="aspectFill"
            />
            <view className="ShotEntry__meta">
              <text className="ShotEntry__title">
                {lastShot.label}截图已生成
              </text>
              <text className="ShotEntry__hint">
                {Math.round(lastShot.width)}×{Math.round(lastShot.height)} ·
                点击全屏查看，支持缩放
              </text>
            </view>
            <text className="ShotEntry__chevron">›</text>
          </view>
        ) : null}
      </DemoCard>
      {viewerOpen && lastShot ? (
        <ScreenshotViewer
          shot={lastShot}
          onClose={() => setViewerOpen(false)}
        />
      ) : null}
    </view>
  );
}

export function AlbumPage() {
  const [result, setResult] = useState<string | null>(null);

  const pick = useCallback(() => {
    'background only';
    albumUtils
      .pick({ maxSelection: 3 })
      .then(async (uris) => {
        if (uris.length === 0) {
          setResult('已取消选择');
          return;
        }
        const lines: string[] = [];
        for (const uri of uris) {
          try {
            const info = await fileSystem.stat(uri);
            const size =
              info.size === null
                ? '未知大小'
                : `${(info.size / 1024).toFixed(1)} KB`;
            lines.push(
              `${info.name} · ${size} · ${info.mimeType ?? '未知类型'}`,
            );
          } catch {
            lines.push(uri);
          }
        }
        setResult(lines.join('\n'));
      })
      .catch((error: Error) => setResult(error.message));
  }, []);

  return (
    <view>
      <ApiName name="albumUtils.pick" />
      <DemoCard
        title="相册"
        desc="调用系统相册选择器挑选图片（最多 3 张），并通过 fileSystem.stat 读取文件元数据。"
      >
        <DemoButton label="从相册选择图片" primary onTap={pick} />
        <ResultLine text={result} placeholder="选中图片的名称 / 大小 / 类型" />
      </DemoCard>
    </view>
  );
}

function formatClock(ms: number): string {
  'background only';
  const totalSeconds = Math.max(0, Math.round(ms / 1000));
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;
  return `${minutes}:${seconds.toString().padStart(2, '0')}`;
}

const PLAYER_STATE_LABELS: Record<string, string> = {
  loading: '加载中',
  paused: '已暂停',
  playing: '播放中',
  stopped: '已停止',
};

/** Local-file playback through the AudioPlayer autolink module. */
export function AudioPlayerPage() {
  const [status, setStatus] = useState('尚未选择音频文件');
  const [playing, setPlaying] = useState(false);
  const playerRef = useRef<AudioPlayerHandle | null>(null);

  const describeState = useCallback((event: AudioPlayerStateEvent) => {
    'background only';
    const label = PLAYER_STATE_LABELS[event.state] ?? event.state;
    const interruption =
      event.interruption === undefined ? '' : ` · 打断：${event.interruption}`;
    setStatus(
      `${label} · ${formatClock(event.positionMs)} / ${formatClock(event.durationMs)}${interruption}`,
    );
  }, []);

  const pick = useCallback(() => {
    'background only';
    fileSystem
      .pick()
      .then(async (uris) => {
        'background only';
        if (uris.length === 0) {
          setStatus('已取消选择');
          return;
        }
        playerRef.current?.destroy();
        setPlaying(false);
        setStatus('加载中 · 0:00 / 0:00');

        const [picked] = uris;
        if (picked === undefined) {
          setStatus('已取消选择');
          return;
        }
        const player = audioPlayer.create({ uri: picked });
        playerRef.current = player;
        player.addEventListener('state', describeState);
        player.addEventListener('state', (event) => {
          'background only';
          setPlaying(event.state === 'playing');
        });
        player.addEventListener('progress', (event) => {
          'background only';
          setStatus(
            `播放中 · ${formatClock(event.positionMs)} / ${formatClock(event.durationMs)}`,
          );
        });
        player.addEventListener('error', (event) => {
          'background only';
          setStatus(`播放错误：${event.error}`);
        });
        try {
          await player.created;
          const props = await player.getProps();
          setStatus(
            `就绪 · ${formatClock(0)} / ${formatClock(props.durationMs)}`,
          );
        } catch (error) {
          setStatus(`无法播放：${(error as Error).message}`);
        }
      })
      .catch((error: Error) => setStatus(`选择失败：${error.message}`));
  }, [describeState]);

  useEffect(() => {
    'background only';
    return () => {
      'background only';
      playerRef.current?.destroy();
      playerRef.current = null;
    };
  }, []);

  const toggle = useCallback(() => {
    'background only';
    const player = playerRef.current;
    if (player === null) return;
    if (playing) {
      player.pause().catch((error: Error) => setStatus(error.message));
    } else {
      player.play().catch((error: Error) => setStatus(error.message));
    }
  }, [playing]);

  const stop = useCallback(() => {
    'background only';
    playerRef.current?.stop().catch((error: Error) => setStatus(error.message));
  }, []);

  const skip = useCallback((deltaSeconds: number) => {
    'background only';
    const player = playerRef.current;
    if (player === null) return;
    player
      .getProps()
      .then((props) => player.seek(props.positionMs + deltaSeconds * 1000))
      .catch((error: Error) => setStatus(error.message));
  }, []);

  return (
    <view>
      <ApiName name="audioPlayer.create" />
      <DemoCard
        title="音频播放"
        desc="从系统文件选择器挑选一个本地音频文件播放；进度与状态经 audioPlayer 事件回传，音频焦点由原生按 media 流自动管理。"
      >
        <DemoButton label="选择音频文件" primary onTap={pick} />
        <DemoButton label={playing ? '暂停' : '播放'} onTap={toggle} />
        <DemoButton label="后退 10 秒" onTap={() => skip(-10)} />
        <DemoButton label="前进 10 秒" onTap={() => skip(10)} />
        <DemoButton label="停止" onTap={stop} />
        <ResultLine text={status} placeholder="播放状态与进度" />
      </DemoCard>
    </view>
  );
}

// Self-contained demo page for the autolinked <module-webview>: it talks to
// the same native modules the template uses (KV / Clipboard / Haptics)
// through window.__lynxNativeBridge, the raw protocol behind
// @lynx-template/autolink-webview-bridge/client. String concatenation
// instead of template literals keeps this embeddable in the TSX template
// literal below.
const WEBVIEW_BRIDGE_DEMO_HTML = [
  '<!DOCTYPE html><html><head><meta charset="utf-8">',
  '<meta name="viewport" content="width=device-width, initial-scale=1">',
  '<style>',
  'body { font-family: -apple-system, sans-serif; margin: 10px; color: #1d1b20; }',
  '.row { display: flex; gap: 8px; margin: 8px 0; flex-wrap: wrap; }',
  'button { padding: 8px 12px; border: 1px solid #cac4d0; border-radius: 8px;',
  '  background: #f3edf7; font-size: 13px; }',
  'button.primary { background: #07c160; border-color: #07c160; color: #fff; }',
  '#out { font-size: 12px; color: #49454f; word-break: break-all; min-height: 16px; }',
  '</style></head><body>',
  '<div class="row">',
  '<button class="primary" onclick="saveKv()">KV 写入</button>',
  '<button onclick="readKv()">KV 读取</button>',
  '<button onclick="copyClip()">剪贴板</button>',
  '<button onclick="buzz()">振动</button>',
  '<button onclick="readDevice()">设备</button>',
  '</div><div id="out">waiting for the bridge…</div>',
  '<script>',
  'var out = document.getElementById("out");',
  'var selfTestStarted = false;',
  'function say(text) { out.textContent = text; }',
  'function call(module, method, args) {',
  '  if (!window.__lynxNativeBridge) { say("bridge unavailable");',
  '    return Promise.reject(new Error("bridge unavailable")); }',
  '  return window.__lynxNativeBridge.invoke(module, method, args);',
  '}',
  'function saveKv() {',
  '  call("KV", "setString", ["webview.counter", String(Date.now())])',
  '    .then(function () { say("KV saved"); },',
  '      function (e) { say("KV save failed: " + e.message); });',
  '}',
  'function readKv() {',
  '  call("KV", "getString", ["webview.counter", null])',
  '    .then(function (r) { say("KV value: " + r[0]); },',
  '      function (e) { say("KV read failed: " + e.message); });',
  '}',
  'function copyClip() {',
  '  call("Clipboard", "setString", ["from webview " + Date.now()])',
  '    .then(function () { return call("Clipboard", "getString", []); })',
  '    .then(function (r) { say("Clipboard: " + r[0]); },',
  '      function (e) { say("Clipboard failed: " + e.message); });',
  '}',
  'function buzz() {',
  '  call("Haptics", "impact", ["light"])',
  '    .then(function () { say("haptic done"); },',
  '      function (e) { say("haptic failed: " + e.message); });',
  '}',
  'function readDevice() {',
  '  call("DeviceInfo", "getInfo", [])',
  '    .then(function (r) {',
  '      var result = JSON.parse(r[0]);',
  '      if (result.error) { throw new Error(result.error); }',
  '      say("Device: " + result.value.manufacturer + " " + result.value.model);',
  '    }, function (e) { say("Device failed: " + e.message); });',
  '}',
  'function runSelfTest() {',
  '  if (selfTestStarted || !window.__lynxNativeBridge) { return; }',
  '  selfTestStarted = true;',
  '  var key = "webview.selftest";',
  '  var expected = "ok-" + Date.now();',
  '  call("KV", "setString", [key, expected])',
  '    .then(function () { return call("KV", "getString", [key, null]); })',
  '    .then(function (r) {',
  '      if (r[0] !== expected) { throw new Error("KV round-trip mismatch"); }',
  '      return call("DeviceInfo", "getInfo", []);',
  '    })',
  '    .then(function (r) {',
  '      var result = JSON.parse(r[0]);',
  '      if (result.error || !result.value || !result.value.model) {',
  '        throw new Error(result.error || "invalid DeviceInfo");',
  '      }',
  '      say("WEBVIEW_BRIDGE_OK · " + result.value.manufacturer + " " + result.value.model);',
  '    })',
  '    .catch(function (e) { say("WEBVIEW_BRIDGE_FAIL · " + e.message); });',
  '}',
  'window.addEventListener("lynx-native-bridge-ready", runSelfTest);',
  'if (window.__lynxNativeBridge) { setTimeout(runSelfTest, 0); }',
  '</script></body></html>',
].join('');

export function WebViewPage() {
  return (
    <view>
      <ApiName name="module-webview" />
      <DemoCard
        title="WebView 模块桥"
        desc="内嵌网页通过 window.__lynxNativeBridge 调用与 Lynx 侧相同的原生模块（KV / 剪贴板 / 振动 / 设备信息），三端宿主行为一致。加载完成后页面会自动跑一轮自检。"
      >
        <module-webview
          className="WebviewBridgeDemo"
          html={WEBVIEW_BRIDGE_DEMO_HTML}
          webview-type="module-bridge"
          params={{
            'module-bridge': {
              modules: ['KV', 'Clipboard', 'Haptics', 'DeviceInfo'],
            },
          }}
        />
      </DemoCard>
    </view>
  );
}
