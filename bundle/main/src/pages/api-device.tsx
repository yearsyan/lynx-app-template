import { useCallback, useEffect, useRef, useState } from '@lynx-js/react';
import { albumUtils } from '@lynx-template/autolink-album-utils';
import { biometric } from '@lynx-template/autolink-biometric';
import { clipboard } from '@lynx-template/autolink-clipboard';
import {
  appSettings,
  battery,
  deviceInfo,
  display,
  type SensorReading,
  type SensorType,
  sensors,
} from '@lynx-template/autolink-device';
import { haptics } from '@lynx-template/autolink-haptics';
import {
  type PermissionStatus,
  type PermissionType,
  permissions,
} from '@lynx-template/autolink-permissions';
import { scanner } from '@lynx-template/autolink-scanner';

import {
  ApiName,
  DemoButton,
  DemoCard,
  ResultLine,
} from '../components/Demo.js';
import { t } from '../i18n.js';

export function DeviceInfoPage() {
  const [result, setResult] = useState<string | null>(null);
  const [widths, setWidths] = useState<string | null>(null);

  const read = useCallback(() => {
    'background only';
    Promise.all([
      deviceInfo.getInfo(),
      display.screenWidth(),
      display.windowWidth(),
      display.lynxViewWidth(),
    ])
      .then(([info, screen, windowWidth, view]) => {
        const traits = [
          info.isTablet ? '平板' : '',
          info.isFoldable ? '折叠屏' : '',
        ]
          .filter((trait) => trait.length > 0)
          .join(' · ');
        setResult(
          `${info.manufacturer} ${info.model}\n系统 ${info.osVersion} · 应用 v${info.appVersion} (${info.appBuild})\n` +
            `包名 ${info.bundleId} · 密度 ${info.density}x · ${info.locale}${traits.length > 0 ? ` · ${traits}` : ''}`,
        );
        setWidths(
          `屏幕 ${Math.round(screen)} / 窗口 ${Math.round(windowWidth)} / LynxView ${Math.round(view)}`,
        );
      })
      .catch((error: Error) => setResult(error.message));
  }, []);

  return (
    <view>
      <ApiName name="deviceInfo.getInfo" />
      <DemoCard
        title="设备信息"
        desc="机型、系统版本、应用版本与包名、屏幕密度、地区语言与三种宽度（屏幕 / 窗口 / LynxView）。"
      >
        <DemoButton label="读取设备信息" primary onTap={read} />
        <ResultLine text={result} placeholder="点击读取本机信息" />
        {widths ? (
          <view className="ResultLine">
            <text className="ResultLine__text">{widths}</text>
          </view>
        ) : null}
      </DemoCard>
    </view>
  );
}

export function BatteryPage() {
  const [result, setResult] = useState<string | null>(null);

  const read = useCallback(() => {
    'background only';
    battery
      .getInfo()
      .then((info) => {
        setResult(
          info.level === null
            ? '该设备无法读取电量（iOS 模拟器返回空）'
            : `电量 ${Math.round(info.level * 100)}% · ${info.charging ? '充电中' : '未充电'}`,
        );
      })
      .catch((error: Error) => setResult(error.message));
  }, []);

  return (
    <view>
      <ApiName name="battery.getInfo" />
      <DemoCard title="电池电量" desc="读取当前电量百分比与充电状态。">
        <DemoButton label="读取电量" primary onTap={read} />
        <ResultLine text={result} placeholder="点击读取电池状态" />
      </DemoCard>
    </view>
  );
}

interface SensorDemoSpec {
  type: SensorType;
  title: string;
  desc: string;
  placeholder: string;
  unavailable: string;
  format: (reading: SensorReading) => string;
}

const SENSOR_SPECS: SensorDemoSpec[] = [
  {
    type: 'accelerometer',
    title: '加速度计',
    desc: '持续输出包含重力的 x/y/z 加速度（m/s²）。',
    placeholder: '开始后可晃动设备观察数值',
    unavailable: '该设备不支持加速度计',
    format: (reading) =>
      reading.type === 'accelerometer'
        ? `x ${reading.x.toFixed(2)} · y ${reading.y.toFixed(2)} · z ${reading.z.toFixed(2)} m/s²`
        : '',
  },
  {
    type: 'compass',
    title: '指南针',
    desc: '磁北朝向 0-360°；iOS 首次使用会请求定位权限。',
    placeholder: '开始后旋转设备观察朝向',
    unavailable: '该设备不支持指南针',
    format: (reading) => {
      if (reading.type !== 'compass') return '';
      const accuracy =
        reading.accuracy < 0 ? '?' : `${Math.round(reading.accuracy)}°`;
      return `朝向 ${Math.round(reading.heading)}° · 精度 ±${accuracy}`;
    },
  },
  {
    type: 'gyroscope',
    title: '陀螺仪',
    desc: '持续输出绕 x/y/z 轴的角速度（rad/s）。',
    placeholder: '开始后转动设备观察角速度',
    unavailable: '该设备不支持陀螺仪',
    format: (reading) =>
      reading.type === 'gyroscope'
        ? `x ${reading.x.toFixed(2)} · y ${reading.y.toFixed(2)} · z ${reading.z.toFixed(2)} rad/s`
        : '',
  },
  {
    type: 'magnetometer',
    title: '磁力计',
    desc: '持续输出设备坐标系下的地磁强度（µT）。',
    placeholder: '开始后转动设备观察磁场变化',
    unavailable: '该设备不支持磁力计',
    format: (reading) =>
      reading.type === 'magnetometer'
        ? `x ${reading.x.toFixed(1)} · y ${reading.y.toFixed(1)} · z ${reading.z.toFixed(1)} µT`
        : '',
  },
  {
    type: 'barometer',
    title: '气压计',
    desc: '输出环境气压（hPa），数值随海拔与天气缓慢变化。',
    placeholder: '开始后读取当前环境气压',
    unavailable: '该设备不支持气压计',
    format: (reading) =>
      reading.type === 'barometer'
        ? `气压 ${reading.pressure.toFixed(1)} hPa`
        : '',
  },
];

function SensorCard({ spec }: { spec: SensorDemoSpec }) {
  const [text, setText] = useState<string | null>(null);
  const [active, setActive] = useState(false);
  const stopRef = useRef<(() => void) | null>(null);

  useEffect(() => {
    'background only';
    return () => {
      'background only';
      stopRef.current?.();
    };
  }, []);

  const toggle = useCallback(() => {
    'background only';
    if (stopRef.current !== null) {
      stopRef.current();
      stopRef.current = null;
      setActive(false);
      setText(null);
      return;
    }
    sensors
      .available(spec.type)
      .then((usable) => {
        if (!usable) {
          setText(spec.unavailable);
          return;
        }
        stopRef.current = sensors.observe(
          spec.type,
          (reading) => {
            'background only';
            if (reading.type !== spec.type) return;
            const value = spec.format(reading);
            if (value.length > 0) {
              setText(value);
            }
          },
          // iOS 通过错误回调报告定位权限被拒绝。
          (message) => setText(`错误：${message}`),
        );
        setActive(true);
      })
      .catch((error: Error) => setText(error.message));
  }, [spec]);

  return (
    <DemoCard title={spec.title} desc={spec.desc}>
      <DemoButton
        label={active ? '停止' : '开始'}
        primary={!active}
        onTap={toggle}
      />
      <ResultLine text={text} placeholder={spec.placeholder} />
    </DemoCard>
  );
}

export function SensorsPage() {
  return (
    <view>
      <ApiName name="sensors.observe" />
      {SENSOR_SPECS.map((spec) => (
        <SensorCard key={spec.type} spec={spec} />
      ))}
    </view>
  );
}

export function BiometricPage() {
  const [result, setResult] = useState<string | null>(null);
  const [signingKeyId, setSigningKeyId] = useState<string | null>(null);

  const check = useCallback(() => {
    'background only';
    biometric
      .checkSupport({ policy: 'biometricWeak' })
      .then((support) => {
        setResult(
          `${support.canAuthenticate ? '可用' : '不可用'} · 类型 ${support.biometryType}\n` +
            `${support.policy} · ${support.reason} · 锁屏凭据${support.deviceCredentialSetup ? '已设置' : '未设置'}`,
        );
      })
      .catch((error: Error) => setResult(error.message));
  }, []);

  const authenticate = useCallback(() => {
    'background only';
    setResult('等待系统认证弹窗…');
    biometric
      .authenticate({
        policy: 'biometricWeak',
        title: t('Lynx 接口演示'),
        reason: t('请通过设备可用的生物认证继续。'),
      })
      .then((outcome) => {
        setResult(
          outcome.success
            ? `系统生物认证通过 ✓ · ${outcome.policy}`
            : `未通过：${outcome.code}`,
        );
      })
      .catch((error: Error) => setResult(error.message));
  }, []);

  const makeKey = useCallback(() => {
    'background only';
    setResult('正在生成硬件签名密钥…');
    biometric
      .createSigningKey({ scope: 'demo' })
      .then((outcome) => {
        if (outcome.success && outcome.keyId !== null) {
          setSigningKeyId(outcome.keyId);
        }
        setResult(
          outcome.success
            ? `密钥已创建：${outcome.keyId}\n${outcome.securityLevel} · 公钥 ${outcome.publicKey?.slice(0, 20)}…`
            : `创建失败：${outcome.code}`,
        );
      })
      .catch((error: Error) => setResult(error.message));
  }, []);

  const sign = useCallback(() => {
    'background only';
    if (signingKeyId === null) {
      setResult('请先生成一把签名密钥');
      return;
    }
    setResult('正在签名本地挑战…');
    // 演示页用随机字节代替服务端 nonce 与规范业务上下文的 SHA-256；
    // 正式业务必须由服务端下发 challenge，并自行计算 contextHash。
    const challenge = binaryToBase64(String.fromCharCode(...randomBytes(32)));
    const contextHash = binaryToBase64(String.fromCharCode(...randomBytes(32)));
    biometric
      .signChallenge({
        keyId: signingKeyId,
        challenge,
        contextHash,
        title: t('Lynx 接口演示'),
        reason: t('请通过生物认证完成签名。'),
      })
      .then((outcome) => {
        setResult(
          outcome.success
            ? `签名成功：${outcome.signature?.slice(0, 24)}…`
            : `签名失败：${outcome.code}`,
        );
      })
      .catch((error: Error) => setResult(error.message));
  }, [signingKeyId]);

  const deleteKey = useCallback(() => {
    'background only';
    if (signingKeyId === null) {
      setResult('当前没有演示密钥');
      return;
    }
    biometric
      .deleteSigningKey({ keyId: signingKeyId })
      .then((outcome) => {
        if (outcome.success) {
          setSigningKeyId(null);
        }
        setResult(
          outcome.success ? '演示密钥已删除' : `删除失败：${outcome.code}`,
        );
      })
      .catch((error: Error) => setResult(error.message));
  }, [signingKeyId]);

  return (
    <view>
      <ApiName name="biometric.authenticate" />
      <DemoCard
        title="生物认证"
        desc="静默能力检查 + 一次系统认证弹窗；设备会使用已配置的人脸或指纹，业务无需也不能指定传感器。"
      >
        <DemoButton label="检查支持情况" onTap={check} />
        <DemoButton label="发起生物认证" primary onTap={authenticate} />
        <ResultLine text={result} placeholder="发起一次系统生物认证" />
      </DemoCard>
      <DemoCard
        title="硬件签名密钥"
        desc="按 scope 创建可轮换的不可导出密钥；签名绑定 keyId、业务上下文摘要与服务端挑战。"
      >
        <DemoButton label="生成签名密钥" onTap={makeKey} />
        <DemoButton label="签名挑战" onTap={sign} />
        <DemoButton label="删除当前密钥" onTap={deleteKey} />
      </DemoCard>
    </view>
  );
}

function randomBytes(length: number): number[] {
  'background only';
  const bytes: number[] = [];
  for (let index = 0; index < length; index += 1) {
    bytes.push(Math.floor(Math.random() * 256));
  }
  return bytes;
}

/** Minimal Base64 encoder (the Lynx runtime has no atob/btoa). */
function binaryToBase64(binary: string): string {
  'background only';
  const alphabet =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  let output = '';
  for (let i = 0; i < binary.length; i += 3) {
    const a = binary.charCodeAt(i);
    const b = binary.charCodeAt(i + 1);
    const c = binary.charCodeAt(i + 2);
    output += alphabet[a >> 2];
    output += alphabet[((a & 3) << 4) | (Number.isNaN(b) ? 0 : b >> 4)];
    const second = Number.isNaN(b) ? 64 : ((b & 15) << 2) | (c >> 6);
    output += second === 64 ? '=' : alphabet[second];
    output += Number.isNaN(c) ? '=' : alphabet[c & 63];
  }
  return output;
}

export function ClipboardPage() {
  const [result, setResult] = useState<string | null>(null);

  const copy = useCallback(() => {
    'background only';
    const value = `lynx-${Date.now()}`;
    clipboard
      .setString(value)
      .then(() => setResult(`已写入：${value}`))
      .catch((error: Error) => setResult(error.message));
  }, []);

  const read = useCallback(() => {
    'background only';
    clipboard
      .getString()
      .then((value) =>
        setResult(value === null ? '剪贴板为空' : `剪贴板内容：${value}`),
      )
      .catch((error: Error) => setResult(error.message));
  }, []);

  return (
    <view>
      <ApiName name="clipboard.setString" />
      <DemoCard title="剪贴板" desc="写入与读取系统剪贴板文本。">
        <DemoButton label="写入随机文本" primary onTap={copy} />
        <DemoButton label="读取剪贴板" onTap={read} />
        <ResultLine text={result} placeholder="先写入，再读取验证" />
      </DemoCard>
    </view>
  );
}

const IMPACTS = ['light', 'medium', 'heavy'] as const;

export function HapticsPage() {
  const [result, setResult] = useState<string | null>(null);

  const run = useCallback((style: (typeof IMPACTS)[number]) => {
    'background only';
    haptics
      .impact(style)
      .then(() => setResult(`已触发 ${style} 振动`))
      .catch((error: Error) => setResult(error.message));
  }, []);

  return (
    <view>
      <ApiName name="haptics.impact" />
      <DemoCard
        title="振动反馈"
        desc="三档物理触感反馈，适合配合按钮点击、开关切换等轻交互。"
      >
        {IMPACTS.map((style) => (
          <DemoButton
            key={style}
            label={`${style} 振动`}
            primary={style === 'medium'}
            onTap={() => run(style)}
          />
        ))}
        <ResultLine text={result} placeholder="点击感受不同强度的振动" />
      </DemoCard>
    </view>
  );
}

function summarizeScan(outcome: {
  success: boolean;
  code: string;
  content: string | null;
  format: string | null;
}): string {
  'background only';
  return outcome.success
    ? `${outcome.format}: ${outcome.content}`
    : `未完成：${outcome.code}`;
}

export function ScannerPage() {
  const [result, setResult] = useState<string | null>(null);

  const scan = useCallback(() => {
    'background only';
    setResult('等待扫码…');
    scanner
      .scan()
      .then((outcome) => setResult(summarizeScan(outcome)))
      .catch((error: Error) => setResult(error.message));
  }, []);

  const scanFromAlbum = useCallback(() => {
    'background only';
    setResult('请选择一张图片…');
    albumUtils
      .pick()
      .then((uris) => {
        const uri = uris[0];
        if (uri === undefined) {
          setResult('已取消选择');
          return;
        }
        return scanner
          .scanFromImage(uri)
          .then((outcome) => setResult(summarizeScan(outcome)));
      })
      .catch((error: Error) => setResult(error.message));
  }, []);

  return (
    <view>
      <ApiName name="scanner.scan" />
      <DemoCard
        title="扫码"
        desc="全屏相机扫码页，支持二维码 / 条码；取消、无权限、图中无码都会以结果码返回。"
      >
        <DemoButton label="打开相机扫码" primary onTap={scan} />
        <DemoButton label="从相册选图识别" onTap={scanFromAlbum} />
        <ResultLine text={result} placeholder="扫码结果展示在这里" />
      </DemoCard>
    </view>
  );
}

const PERMISSION_ITEMS: {
  type: PermissionType;
  label: string;
}[] = [
  { type: 'notifications', label: '通知' },
  { type: 'camera', label: '相机' },
  { type: 'photoLibrary', label: '相册' },
  { type: 'microphone', label: '麦克风' },
];

const PERMISSION_STATUS_TEXT: Record<PermissionStatus, string> = {
  granted: '已授权',
  limited: '部分授权',
  denied: '已拒绝',
  notDetermined: '未请求',
  restricted: '受系统限制',
};

export function PermissionsPage() {
  const [result, setResult] = useState<string | null>(null);

  const run = useCallback((label: string, call: () => Promise<string>) => {
    'background only';
    call()
      .then((text) => setResult(`${t(label)} · ${t(text)}`))
      .catch((error: Error) => setResult(`${label} · ${error.message}`));
  }, []);

  const openSettings = useCallback(() => {
    'background only';
    appSettings
      .open()
      .then(() => setResult('已请求打开系统应用设置'))
      .catch((error: Error) => setResult(error.message));
  }, []);

  return (
    <view>
      <ApiName name="permissions.check / request" />
      <DemoCard
        title="运行时权限"
        desc="统一的权限查询与申请：状态归一为已授权/部分授权/已拒绝/未请求/受限制。Android 无法区分「未请求」与「拒绝后不再询问」，因此 denied 后申请仍可能弹窗；iOS 拒绝后需去系统设置。"
      >
        <DemoButton label="打开应用设置" onTap={openSettings} />
        {PERMISSION_ITEMS.map((item) => (
          <DemoCard key={item.type} title={item.label}>
            <DemoButton
              label="查询状态"
              primary
              onTap={() =>
                run(item.label, () =>
                  permissions
                    .check(item.type)
                    .then((state) => PERMISSION_STATUS_TEXT[state.status]),
                )
              }
            />
            <DemoButton
              label="弹出申请"
              onTap={() =>
                run(item.label, () =>
                  permissions
                    .request(item.type)
                    .then((state) => PERMISSION_STATUS_TEXT[state.status]),
                )
              }
            />
          </DemoCard>
        ))}
        <ResultLine text={result} placeholder="查询或申请一项权限" />
      </DemoCard>
    </view>
  );
}
