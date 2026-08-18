import { useCallback, useState } from '@lynx-js/react';

import '@lynx-template/autolink-webview-bridge';

import { albumUtils, fileSystem, screenshot } from '@lynx-app/native-bridge';

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

function summarizeShot(
  label: string,
  result: { uri: string; width: number; height: number },
): string {
  'background only';
  return `${label}截图：${Math.round(result.width)}x${Math.round(result.height)} · ${
    result.uri.split('/').pop() ?? result.uri
  }`;
}

export function ScreenshotPage() {
  const [result, setResult] = useState<string | null>(null);

  const capture = useCallback(
    (
      label: string,
      call: () => Promise<{ uri: string; width: number; height: number }>,
    ) => {
      'background only';
      call()
        .then((shot) => setResult(summarizeShot(label, shot)))
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
      </DemoCard>
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

// Self-contained demo page for the autolinked <module-webview>: it talks to
// the same native modules the template uses (KV / Clipboard / Haptics)
// through window.__lynxNativeBridge, the raw protocol behind
// @lynx-app/webview-bridge. String concatenation instead of template literals
// keeps this embeddable in the TSX template literal below.
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
