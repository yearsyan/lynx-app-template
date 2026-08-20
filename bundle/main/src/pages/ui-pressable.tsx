import { useCallback, useState } from '@lynx-js/react';

import { ApiName, DemoCard, ResultLine } from '../components/Demo.js';
import '../components/native-elements.js';

const BANNERS = [
  ['夏日限定', '按住可看原生状态层反馈'],
  ['新品首发', '上下拖动时不会进入按下态'],
  ['会员专享', '快速甩动后点按可验证惯性刹停'],
  ['周末活动', '滚动手势最终不会发出 press'],
  ['精选内容', '只有完整原生点击才跨线程回调'],
  ['附近推荐', '移动超过平台 touch slop 即取消'],
  ['订阅更新', 'ACTION_CANCEL / touchesCancelled 会复位'],
  ['热门榜单', '视觉反馈不触发 React 重新渲染'],
  ['创作者计划', 'Android、iOS、HarmonyOS 同一标签'],
  ['更多内容', '继续滚动以测试长列表行为'],
] as const;

export function PressableViewPage() {
  const [pressCount, setPressCount] = useState(0);
  const [lastPressed, setLastPressed] = useState<string | null>(null);

  const recordPress = useCallback((label: string) => {
    'background only';
    setPressCount((count) => count + 1);
    setLastPressed(label);
  }, []);

  return (
    <view>
      <ApiName name="<pressable-view />" />
      <DemoCard
        title="原生 Pressable"
        desc="绿色按钮使用更深的状态层；视觉反馈与滚动手势仲裁都在平台 UI 线程，JS 只接收最终一次 press。"
      >
        <pressable-view
          id="pressable-primary"
          className="NativePressable NativePressable--primary"
          active-opacity={1}
          pressed-overlay-color="rgba(0, 0, 0, 0.12)"
          accessibility-element
          accessibility-label="原生点击测试"
          accessibility-traits="button"
          bindpress={() => recordPress('原生点击测试')}
        >
          <view className="NativePressable__surface NativePressable__surface--primary">
            <text className="NativePressable__primaryLabel">点按测试</text>
          </view>
        </pressable-view>
        <pressable-view
          className="NativePressable NativePressable--disabled"
          disabled
          accessibility-element
          accessibility-label="禁用状态"
          accessibility-traits="disabled"
        >
          <view className="NativePressable__surface NativePressable__surface--disabled">
            <text className="NativePressable__disabledLabel">禁用状态</text>
          </view>
        </pressable-view>
        <ResultLine
          text={
            lastPressed === null
              ? null
              : `press × ${pressCount} · 最后：${lastPressed}`
          }
          placeholder="尚未收到 press；滚动和刹停触摸不应改变计数"
        />
      </DemoCard>

      <DemoCard
        title="滚动 / 甩动 / 刹停验证"
        desc="浅色横幅使用 8% 黑色状态层。在横幅上慢拖、快速甩动，再用手指点停惯性；横幅不应闪烁或增加计数。"
      >
        {BANNERS.map(([title, subtitle], index) => (
          <pressable-view
            key={title}
            id={`pressable-banner-${index}`}
            className="PressableBanner"
            active-opacity={1}
            pressed-overlay-color="rgba(0, 0, 0, 0.08)"
            accessibility-element
            accessibility-label={title}
            accessibility-traits="button"
            bindpress={() => recordPress(title)}
          >
            <view className="PressableBanner__surface">
              <view className="PressableBanner__copy">
                <text className="PressableBanner__title">{title}</text>
                <text className="PressableBanner__subtitle">{subtitle}</text>
              </view>
              <text className="PressableBanner__chevron">›</text>
            </view>
          </pressable-view>
        ))}
      </DemoCard>
    </view>
  );
}
