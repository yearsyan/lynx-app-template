import { useCallback, useState } from '@lynx-js/react';

import { ApiName, DemoCard, ResultLine } from '../components/Demo.js';
import '../components/native-elements.js';
import { t } from '../i18n.js';

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
  const [eventCount, setEventCount] = useState(0);
  const [lastEvent, setLastEvent] = useState<string | null>(null);

  const recordEvent = useCallback((kind: '点击' | '长按', label: string) => {
    'background only';
    setEventCount((count) => count + 1);
    setLastEvent(`${kind} · ${label}`);
  }, []);

  return (
    <view>
      <ApiName name="<pressable-view />" />
      <DemoCard
        title="长按与系统触感"
        desc="分别长按下面两个按钮：约 500ms 后只回调一次 longpress，松手不会补发 press；第二个按钮还会触发系统线性马达。"
      >
        <pressable-view
          id="pressable-long-no-haptic"
          className="NativePressable NativePressable--secondary"
          active-opacity={1}
          pressed-overlay-color="rgba(0, 0, 0, 0.08)"
          accessibility-element
          accessibility-label={t('长按测试，不带系统触感')}
          accessibility-traits="button"
          bindpress={() => recordEvent('点击', '无触感按钮')}
          bindlongpress={() => recordEvent('长按', '未启用系统触感')}
        >
          <view className="NativePressable__surface NativePressable__surface--secondary">
            <text className="NativePressable__secondaryLabel">
              {t('长按测试（无触感）')}
            </text>
          </view>
        </pressable-view>
        <pressable-view
          id="pressable-long-haptic"
          className="NativePressable NativePressable--primary"
          active-opacity={1}
          pressed-overlay-color="rgba(0, 0, 0, 0.12)"
          long-press-haptic
          accessibility-element
          accessibility-label={t('长按测试，带系统触感')}
          accessibility-traits="button"
          bindpress={() => recordEvent('点击', '触感按钮')}
          bindlongpress={() => recordEvent('长按', '已启用系统触感')}
        >
          <view className="NativePressable__surface NativePressable__surface--primary">
            <text className="NativePressable__primaryLabel">
              {t('长按测试（系统触感）')}
            </text>
          </view>
        </pressable-view>
        <pressable-view
          className="NativePressable NativePressable--disabled"
          disabled
          accessibility-element
          accessibility-label={t('禁用状态')}
          accessibility-traits="disabled"
        >
          <view className="NativePressable__surface NativePressable__surface--disabled">
            <text className="NativePressable__disabledLabel">
              {t('禁用状态')}
            </text>
          </view>
        </pressable-view>
        <ResultLine
          text={
            lastEvent === null
              ? null
              : `事件 × ${eventCount} · 最后：${lastEvent}`
          }
          placeholder="尚未收到事件；请分别长按两个按钮进行对比"
        />
      </DemoCard>

      <DemoCard
        title="滚动 / 甩动 / 刹停验证"
        desc="横幅也支持长按，但未开启马达。慢拖、快速甩动或点停惯性都不应触发点击/长按。"
      >
        {BANNERS.map(([title, subtitle], index) => (
          <pressable-view
            key={title}
            id={`pressable-banner-${index}`}
            className="PressableBanner"
            active-opacity={1}
            pressed-overlay-color="rgba(0, 0, 0, 0.08)"
            accessibility-element
            accessibility-label={t(title)}
            accessibility-traits="button"
            bindpress={() => recordEvent('点击', title)}
            bindlongpress={() => recordEvent('长按', `${title}（无触感）`)}
          >
            <view className="PressableBanner__surface">
              <view className="PressableBanner__copy">
                <text className="PressableBanner__title">{t(title)}</text>
                <text className="PressableBanner__subtitle">{t(subtitle)}</text>
              </view>
              <text className="PressableBanner__chevron">›</text>
            </view>
          </pressable-view>
        ))}
      </DemoCard>
    </view>
  );
}
