import { useCallback, useInitData, useState } from '@lynx-js/react';

import type { RoutePresentOptions } from '@lynx-template/autolink-navigation';
import { router } from '@lynx-template/autolink-navigation';
import { useRouteParams } from '@lynx-template/autolink-navigation/react';

import {
  ApiName,
  DemoButton,
  DemoCard,
  ResultLine,
} from '../components/Demo.js';

/**
 * Demonstrates `router.open({ animation: 'present' })`: the host snapshots
 * the current page, opens this page again with no system transition, and
 * replays the snapshot behind the (transparent) content. The same component
 * renders both roles: the pushed entry card, and the chrome-less modal page
 * when it is itself the present route.
 */
export function RoutePresentPage() {
  const initData = useInitData();
  const params = useRouteParams<{ page?: string; mode?: string }>();
  const isPresentRoute = initData?.route?.animation === 'present';

  if (params.mode === 'fullscreen') {
    return <PresentFullscreenPage />;
  }
  if (isPresentRoute) {
    return <PresentModalPage />;
  }
  return <PresentEntryPage />;
}

function PresentEntryPage() {
  const [result, setResult] = useState<string | null>(null);

  const openPresent = useCallback((present?: RoutePresentOptions) => {
    router
      .open({
        bundle: 'main',
        animation: 'present',
        // The revealed snapshot margins are black, so keep the status bar
        // readable while this page is up.
        statusBarStyle: 'light-content',
        present,
        params: { page: 'routepresent' },
      })
      .then(() => setResult('present 页面已关闭'))
      .catch((error: Error) =>
        console.error(`Unable to open present route: ${error.message}`),
      );
  }, []);

  return (
    <view>
      <ApiName name="router.open · animation: 'present'" />
      <DemoCard
        title="present 转场"
        desc="打开前对当前页面截图，新页面首帧即以截图为背景（与上一页像素一致、无闪白）。默认内容不做透明度变化，从屏幕下方 0 可见面积推入，关闭时再推出；入场、出场以及 iOS/Android 的交互返回都可单独配置。"
      >
        <DemoButton
          label="以 present 打开"
          primary
          onTap={() => openPresent()}
        />
        <DemoButton
          label="模糊背景（降采样截图）"
          onTap={() => openPresent({ backdropBlur: true })}
        />
        <DemoButton
          label="入场仅淡入 / 出场默认推出"
          onTap={() => openPresent({ enter: { opacity: true, push: false } })}
        />
        <DemoButton
          label="入场默认推入 / 出场仅淡出"
          onTap={() => openPresent({ exit: { opacity: true, push: false } })}
        />
        <DemoButton
          label="仅背景缩放"
          onTap={() =>
            openPresent({ enter: { push: false }, exit: { push: false } })
          }
        />
        <DemoButton
          label="仅内容入出场"
          onTap={() => openPresent({ backdropTransition: false })}
        />
        <DemoButton
          label="清除全部动画"
          onTap={() =>
            openPresent({
              backdropTransition: false,
              enter: { push: false },
              exit: { push: false },
            })
          }
        />
        <DemoButton
          label="自定义遮罩 #99CC3300"
          onTap={() => openPresent({ scrimColor: '#99CC3300' })}
        />
        <DemoButton
          label="iOS 侧滑下移退出"
          onTap={() => openPresent({ iosSwipeDown: true })}
        />
        <DemoButton
          label="Android 预测返回下移"
          onTap={() => openPresent({ androidPredictiveBackDown: true })}
        />
        <ResultLine
          text={result}
          placeholder="打开对应演示后，从 iOS 左边缘侧滑或使用 Android 返回手势"
        />
      </DemoCard>
    </view>
  );
}

function PresentModalPage() {
  const close = useCallback(() => {
    router.close().catch(() => {});
  }, []);
  const openFullscreen = useCallback(() => {
    router
      .open({
        bundle: 'main',
        animation: 'default',
        statusBarStyle: 'dark-content',
        params: { page: 'routepresent', mode: 'fullscreen' },
      })
      .catch((error: Error) =>
        console.error(`Unable to open fullscreen route: ${error.message}`),
      );
  }, []);

  return (
    <view className="PresentRoute__root">
      {/* The dimmed gap above the card is painted by the native scrim over
          the shrunken snapshot; this transparent view catches close taps. */}
      <view className="PresentRoute__scrim" bindtap={close} />
      <view className="PresentRoute__sheet">
        <view className="PresentRoute__handle" />
        <text className="PresentRoute__title">present 转场</text>
        <text className="PresentRoute__desc">
          背后露出的“上一页”是打开瞬间截取的截图背景；系统返回、点按遮罩或下方按钮都会先放大复原背景，再无缝切回真实的上一页。
        </text>
        <DemoButton label="打开全屏页面" primary onTap={openFullscreen} />
        <DemoButton label="关闭 Sheet" onTap={close} />
      </view>
    </view>
  );
}

function PresentFullscreenPage() {
  const close = useCallback(() => {
    router.close().catch(() => {});
  }, []);

  return (
    <view>
      <ApiName name="router.open · full screen" />
      <DemoCard
        title="全屏页面"
        desc="这个页面由 present Sheet 内再次调用 router.open 打开，是导航栈中的普通全屏路由；关闭后会回到原来的 Sheet。"
      >
        <DemoButton label="关闭全屏页面" primary onTap={close} />
      </DemoCard>
    </view>
  );
}
