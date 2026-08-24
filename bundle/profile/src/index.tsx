import {
  root,
  useCallback,
  useEffect,
  useInitData,
  useState,
} from '@lynx-js/react';

import {
  readColorScheme,
  readSafeAreaInsets,
  statusBar,
} from '@lynx-template/autolink-device';
import type { ShareOutcome } from '@lynx-template/autolink-share';
import { share } from '@lynx-template/autolink-share';

import './style.css';

const PAGE_VERSION = 'v2';

/**
 * The share capability split out of the `main` showcase bundle. It is
 * declared with `downloadAt: ['main']`, so the host preloads its OTA update
 * shortly after main's first screen; opening it from main routes across
 * bundles (`router.open({ bundle: 'profile' })`).
 */
function App() {
  const initData = useInitData();
  const colorScheme = readColorScheme(initData);
  const insets = readSafeAreaInsets(initData);
  const topInset = insets.top > 0 ? insets.top : 48;
  const [result, setResult] = useState<string | null>(null);

  const themeClass = colorScheme === 'dark' ? 'theme-dark' : 'theme-light';

  useEffect(() => {
    'background only';
    statusBar
      .setStyle(colorScheme === 'dark' ? 'light-content' : 'dark-content')
      .catch(() => {});
  }, [colorScheme]);

  const run = useCallback(
    (label: string, action: () => Promise<ShareOutcome>) => {
      'background only';
      setResult(`${label}：分享面板已打开…`);
      action()
        .then((outcome) => {
          if (outcome.code === 'sent') {
            setResult(
              `${label}：已交给目标${
                outcome.activityType === null
                  ? ''
                  : `（${outcome.activityType}）`
              }`,
            );
          } else if (outcome.code === 'dismissed') {
            setResult(`${label}：已取消`);
          } else {
            setResult(`${label}：${outcome.message || outcome.code}`);
          }
        })
        .catch((error: Error) => setResult(`${label}：${error.message}`));
    },
    [],
  );

  const shareText = useCallback(() => {
    'background only';
    run('文本', () =>
      share.open({
        title: 'Lynx Template · profile',
        text: '系统分享能力已拆分到独立的 profile bundle（OTA 预下载验证）。',
      }),
    );
  }, [run]);

  const shareLink = useCallback(() => {
    'background only';
    run('链接', () =>
      share.open({
        title: 'Lynx',
        text: 'Lynx 跨端框架',
        url: 'https://lynxjs.org',
      }),
    );
  }, [run]);

  return (
    <view className={`page ${themeClass}`}>
      <view className="navbar" style={{ paddingTop: `${topInset}px` }}>
        <text className="navbar__title">系统分享 · profile {PAGE_VERSION}</text>
      </view>
      <scroll-view
        className="page__scroll"
        scroll-orientation="vertical"
        scroll-bar-enable={false}
      >
        <view className="card">
          <text className="card__title">share.open</text>
          <text className="card__desc">
            这个页面来自独立 bundle「profile」，单独构建、通过 OTA 预下载后由
            main 跨 bundle 路由打开。
          </text>
          <view className="button" bindtap={shareText}>
            <text className="button__label">分享文本</text>
          </view>
          <view className="button button--primary" bindtap={shareLink}>
            <text className="button__label button__label--primary">
              分享链接
            </text>
          </view>
          {result === null ? null : (
            <text className="card__result">{result}</text>
          )}
          <text className="card__version">bundle 版本：{PAGE_VERSION}</text>
        </view>
      </scroll-view>
    </view>
  );
}

root.render(<App />);

if (import.meta.webpackHot) import.meta.webpackHot.accept();
