import { useCallback, useState } from '@lynx-js/react';
import type { BackEvent } from '@lynx-template/autolink-navigation';
import {
  PredictiveBackOverlay,
  type PredictiveBackOverlayDismissReason,
  usePredictiveBackOverlay,
} from '@lynx-template/autolink-navigation/react';

import {
  ApiName,
  DemoButton,
  DemoCard,
  ResultLine,
} from '../components/Demo.js';

type OverlayLayer = '第一层' | '第二层';

function describeBackEvent(layer: OverlayLayer, event: BackEvent): string {
  'background only';
  const phase = {
    start: '开始',
    progress: '进行中',
    cancel: '取消并复位',
    commit: '提交关闭',
  }[event.phase];
  const gesture =
    event.gestureId === undefined ? '' : ` · gesture #${event.gestureId}`;
  return `${layer}：返回${phase} · ${event.source}${gesture}`;
}

export function BackOverlayPage() {
  const first = usePredictiveBackOverlay();
  const second = usePredictiveBackOverlay();
  const [result, setResult] = useState('尚未打开弹层');
  const [lastBackEvent, setLastBackEvent] = useState<string | null>(null);
  const [dragEnabled, setDragEnabled] = useState(true);

  const openFirst = useCallback(() => {
    'background only';
    setResult('第一层已打开；返回会先消费这一层');
    setLastBackEvent(null);
    first.present();
  }, [first.present]);

  const openSecond = useCallback(() => {
    'background only';
    setResult('第二层已入栈；下一次返回只关闭第二层');
    second.present();
  }, [second.present]);

  const closeFirst = useCallback(() => {
    'background only';
    first.dismiss();
    setResult('第一层由页面按钮关闭');
  }, [first.dismiss]);

  const closeSecond = useCallback(() => {
    'background only';
    second.dismiss();
    setResult('第二层由页面按钮关闭，第一层仍然保留');
  }, [second.dismiss]);

  const toggleDrag = useCallback(() => {
    'background only';
    setDragEnabled((enabled) => !enabled);
  }, []);

  const handleFirstOpenChange = useCallback(
    (open: boolean, reason: PredictiveBackOverlayDismissReason) => {
      'background only';
      first.setOpen(open);
      if (!open) {
        const message = {
          back: '返回已关闭第一层；返回栈现在为空',
          backdrop: '点击遮罩关闭了第一层',
          drag: '向下拖动关闭了第一层',
        }[reason];
        setResult(message);
      }
    },
    [first.setOpen],
  );

  const handleSecondOpenChange = useCallback(
    (open: boolean, reason: PredictiveBackOverlayDismissReason) => {
      'background only';
      second.setOpen(open);
      if (!open) {
        const message = {
          back: '返回只关闭了栈顶第二层；第一层仍然打开',
          backdrop: '点击遮罩关闭了第二层；第一层仍然打开',
          drag: '向下拖动关闭了第二层；第一层仍然打开',
        }[reason];
        setResult(message);
      }
    },
    [second.setOpen],
  );

  const handleFirstBackEvent = useCallback((event: BackEvent) => {
    'background only';
    setLastBackEvent(describeBackEvent('第一层', event));
  }, []);

  const handleSecondBackEvent = useCallback((event: BackEvent) => {
    'background only';
    setLastBackEvent(describeBackEvent('第二层', event));
  }, []);

  return (
    <view>
      <ApiName name="<PredictiveBackOverlay />" />
      <DemoCard
        title="原生跟手底部弹层"
        desc="外观和出现 / 消失节奏对齐 LynxUI Sheet。Android / iOS 的系统返回和向下拖动都在 UI 线程直接更新位移与遮罩，不会逐帧跨桥调用 JavaScript。"
      >
        <view className="BackOverlayDemo__flow">
          <view className="BackOverlayDemo__flowStep BackOverlayDemo__flowStep--active">
            <text className="BackOverlayDemo__flowIndex">1</text>
            <text className="BackOverlayDemo__flowLabel">打开第一层</text>
          </view>
          <text className="BackOverlayDemo__flowArrow">›</text>
          <view className="BackOverlayDemo__flowStep">
            <text className="BackOverlayDemo__flowIndex">2</text>
            <text className="BackOverlayDemo__flowLabel">叠加第二层</text>
          </view>
          <text className="BackOverlayDemo__flowArrow">›</text>
          <view className="BackOverlayDemo__flowStep">
            <text className="BackOverlayDemo__flowIndex">↩</text>
            <text className="BackOverlayDemo__flowLabel">逐层返回</text>
          </view>
        </view>
        <DemoButton label="打开第一层弹层" primary onTap={openFirst} />
        <DemoButton
          label={`跟手下拉关闭：${dragEnabled ? '开启' : '关闭'}`}
          onTap={toggleDrag}
        />
        <ResultLine text={result} placeholder="尚未操作" />
        <ResultLine
          text={lastBackEvent}
          placeholder="返回生命周期事件会显示在这里"
        />
      </DemoCard>

      <DemoCard
        title="验证要点"
        desc="连续打开两层后，第一次返回或下拉只关闭第二层，第二次才关闭第一层。下拉距离不足时会原生回弹且不会出栈。"
      >
        <view className="BackOverlayDemo__checks">
          <text className="BackOverlayDemo__check">• 后进先出（LIFO）</text>
          <text className="BackOverlayDemo__check">
            • 单次手势固定消费同一层
          </text>
          <text className="BackOverlayDemo__check">
            • Android / iOS 原生逐帧动画
          </text>
          <text className="BackOverlayDemo__check">
            • 下拉超过阈值关闭，否则回弹
          </text>
        </view>
      </DemoCard>

      <PredictiveBackOverlay
        open={first.open}
        onOpenChange={handleFirstOpenChange}
        onBackEvent={handleFirstBackEvent}
        backdropColor="rgba(0, 0, 0, 0.46)"
        motion="sheet"
        dragToDismiss={dragEnabled}
        style={{ zIndex: 1000 }}
        contentClassName="BackOverlayDemo__sheet"
      >
        <view className="BackOverlayDemo__handle" />
        <view className="BackOverlayDemo__layerBadge">
          <text className="BackOverlayDemo__layerBadgeText">
            返回栈 · 第 1 层
          </text>
        </view>
        <text className="BackOverlayDemo__sheetTitle">底部弹层</text>
        <text className="BackOverlayDemo__sheetDesc">
          向下拖动会跟随手指移动；松手后超过阈值关闭，否则回弹。也可以继续打开第二层，验证返回栈顺序。
        </text>
        <DemoButton label="在上方再打开第二层" primary onTap={openSecond} />
        <DemoButton label="直接关闭第一层" onTap={closeFirst} />
      </PredictiveBackOverlay>

      <PredictiveBackOverlay
        open={second.open}
        onOpenChange={handleSecondOpenChange}
        onBackEvent={handleSecondBackEvent}
        backdropColor="rgba(8, 23, 48, 0.38)"
        motion="sheet"
        dragToDismiss={dragEnabled}
        style={{ zIndex: 1001 }}
        contentClassName="BackOverlayDemo__sheet BackOverlayDemo__sheet--second"
      >
        <view className="BackOverlayDemo__handle BackOverlayDemo__handle--blue" />
        <view className="BackOverlayDemo__layerBadge BackOverlayDemo__layerBadge--blue">
          <text className="BackOverlayDemo__layerBadgeText BackOverlayDemo__layerBadgeText--blue">
            返回栈 · 第 2 层（栈顶）
          </text>
        </view>
        <text className="BackOverlayDemo__sheetTitle">栈顶弹层</text>
        <text className="BackOverlayDemo__sheetDesc">
          这是当前栈顶。系统返回、点击遮罩或向下拖动都只会关闭这一层，下面的第一层不会被同一次操作消费。
        </text>
        <DemoButton label="关闭栈顶，保留第一层" primary onTap={closeSecond} />
      </PredictiveBackOverlay>
    </view>
  );
}
