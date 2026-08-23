import { useCallback, useState } from '@lynx-js/react';
import { display, statusBar } from '@lynx-template/autolink-device';
import { localNotification } from '@lynx-template/autolink-local-notification';
import {
  type PermissionStatus,
  permissions,
} from '@lynx-template/autolink-permissions';
import { toast } from '@lynx-template/autolink-toast';

import {
  ApiName,
  DemoButton,
  DemoCard,
  ResultLine,
} from '../components/Demo.js';
import { t } from '../i18n.js';

const PERMISSION_STATUS_TEXT: Record<PermissionStatus, string> = {
  granted: '已授权',
  limited: '部分授权',
  denied: '已拒绝',
  notDetermined: '未请求',
  restricted: '受系统限制',
};

export function ToastPage() {
  const [result, setResult] = useState<string | null>(null);

  const run = useCallback((label: string, call: () => Promise<void>) => {
    'background only';
    call()
      .then(() => setResult(`${t(label)} · ${t('已弹出')}`))
      .catch((error: Error) => setResult(`${label} · ${error.message}`));
  }, []);

  return (
    <view>
      <ApiName name="toast.show" />
      <DemoCard
        title="消息提示"
        desc="窗口内的原生 Toast：可自定义颜色与图标，无需通知权限，新的 Toast 会替换上一条。"
      >
        <DemoButton
          label="默认提示"
          primary
          onTap={() => run('info', () => toast.info(t('这是一条默认提示')))}
        />
        <DemoButton
          label="成功提示"
          onTap={() => run('success', () => toast.success(t('保存成功')))}
        />
        <DemoButton
          label="失败提示"
          onTap={() => run('error', () => toast.error(t('操作失败，请重试')))}
        />
        <DemoButton
          label="自定义颜色 · 无图标"
          onTap={() =>
            run('custom', () =>
              toast.show(t('自定义背景色，3 秒消失'), {
                backgroundColor: '#FF6750A4',
                showIcon: false,
                durationMs: 3000,
              }),
            )
          }
        />
        <ResultLine text={result} placeholder="点击上方按钮弹出 Toast" />
      </DemoCard>
    </view>
  );
}

export function StatusBarPage() {
  const [result, setResult] = useState<string | null>(null);

  const apply = useCallback((style: 'dark-content' | 'light-content') => {
    'background only';
    statusBar
      .setStyle(style)
      .then(() =>
        setResult(
          style === 'dark-content' ? '已切换为深色文字' : '已切换为浅色文字',
        ),
      )
      .catch((error: Error) => setResult(error.message));
  }, []);

  return (
    <view>
      <ApiName name="statusBar.setStyle" />
      <DemoCard
        title="状态栏样式"
        desc="切换系统状态栏前景色：深色文字适合浅色背景，浅色文字适合深色背景。"
      >
        <DemoButton
          label="深色文字"
          primary
          onTap={() => apply('dark-content')}
        />
        <DemoButton label="浅色文字" onTap={() => apply('light-content')} />
        <ResultLine text={result} placeholder="观察页面顶部状态栏变化" />
      </DemoCard>
    </view>
  );
}

export function BrightnessPage() {
  const [result, setResult] = useState<string | null>(null);
  const [keepOn, setKeepOn] = useState(false);

  const read = useCallback(() => {
    'background only';
    display
      .getBrightness()
      .then((value) => setResult(`当前亮度 ${Math.round(value * 100)}%`))
      .catch((error: Error) => setResult(error.message));
  }, []);

  const change = useCallback((delta: number) => {
    'background only';
    display
      .getBrightness()
      .then((current) => {
        const next = Math.min(1, Math.max(0, current + delta));
        return display.setBrightness(next).then(() => {
          setResult(`亮度已设为 ${Math.round(next * 100)}%`);
        });
      })
      .catch((error: Error) => setResult(error.message));
  }, []);

  const toggleKeepOn = useCallback(() => {
    'background only';
    const next = !keepOn;
    display
      .setKeepScreenOn(next)
      .then(() => {
        setKeepOn(next);
        setResult(next ? '已开启屏幕常亮' : '已关闭屏幕常亮');
      })
      .catch((error: Error) => setResult(error.message));
  }, [keepOn]);

  return (
    <view>
      <ApiName name="display.setBrightness" />
      <DemoCard
        title="屏幕亮度"
        desc="窗口级亮度 0-100%：应用前台期间生效，退后台后系统恢复；常亮仅在本应用可见时保持。"
      >
        <DemoButton label="读取当前亮度" primary onTap={read} />
        <DemoButton label="降低 10%" onTap={() => change(-0.1)} />
        <DemoButton label="提高 10%" onTap={() => change(0.1)} />
        <DemoButton
          label={keepOn ? '关闭屏幕常亮' : '开启屏幕常亮'}
          onTap={toggleKeepOn}
        />
        <ResultLine text={result} placeholder="读取或调整窗口亮度" />
      </DemoCard>
    </view>
  );
}

export function LocalNotificationPage() {
  const [result, setResult] = useState<string | null>(null);

  const run = useCallback((label: string, call: () => Promise<string>) => {
    'background only';
    call()
      .then((text) => setResult(`${t(label)} · ${t(text)}`))
      .catch((error: Error) => setResult(`${label} · ${error.message}`));
  }, []);

  /** Ensures the notification permission is granted before posting. */
  const notify = useCallback(
    (delayMs: number) => {
      'background only';
      run(delayMs === 0 ? '立即通知' : '5 秒定时', async () => {
        const state = await permissions.request('notifications');
        if (state.status !== 'granted' && state.status !== 'limited') {
          return t('未获得通知权限（{status}）', {
            status: t(PERMISSION_STATUS_TEXT[state.status]),
          });
        }
        const outcome = await localNotification.notify({
          id: `demo-${delayMs}`,
          title: delayMs === 0 ? t('Lynx 本地通知') : t('Lynx 定时通知'),
          body:
            delayMs === 0
              ? t('来自 LocalNotification 模块的即时通知。')
              : t('这条通知在 5 秒前由 AlarmManager / 系统触发器排期。'),
          delayMs,
        });
        return outcome.success ? '已发送（或已排期）' : outcome.code;
      });
    },
    [run],
  );

  return (
    <view>
      <ApiName name="localNotification.notify / cancel" />
      <DemoCard
        title="本地通知"
        desc="通过系统通知中心发送通知：权限申请走 Permissions 模块；定时通知在 Android 用 AlarmManager 排期（App 被杀后仍会送达），HarmonyOS 为进程内定时。"
      >
        <DemoButton label="发送立即通知" primary onTap={() => notify(0)} />
        <DemoButton label="发送 5 秒定时通知" onTap={() => notify(5000)} />
        <DemoButton
          label="取消定时通知"
          onTap={() =>
            run('取消', () =>
              localNotification
                .cancel('demo-5000')
                .then(() => '已取消排期与已送达'),
            )
          }
        />
        <DemoButton
          label="取消全部"
          onTap={() =>
            run('全部取消', () =>
              localNotification.cancelAll().then(() => '已清除本应用通知'),
            )
          }
        />
        <ResultLine text={result} placeholder="点击发送时自动申请通知权限" />
      </DemoCard>
    </view>
  );
}
