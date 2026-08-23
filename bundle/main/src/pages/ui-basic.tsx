import type { InputRef } from '@lynx-js/lynx-ui';
import {
  Button,
  Input,
  KeyboardAwareTrigger,
  SliderIndicator,
  SliderRoot,
  SliderThumb,
  SliderTrack,
  TextArea,
} from '@lynx-js/lynx-ui';
import { useEffect, useInitData, useRef, useState } from '@lynx-js/react';
import { readColorScheme } from '@lynx-template/autolink-device';
import { router } from '@lynx-template/autolink-navigation';
import { useRouteContentInsetBottom } from '@lynx-template/autolink-navigation/react';

import {
  ApiName,
  DemoButton,
  DemoCard,
  ResultLine,
} from '../components/Demo.js';
import { useKeyboard } from '../hooks/useKeyboard.js';
import { t } from '../i18n.js';

export function ButtonPage() {
  const [result, setResult] = useState<string | null>(null);

  return (
    <view>
      <ApiName name="<Button />" />
      <DemoCard
        title="按钮"
        desc="@lynx-js/lynx-ui 的无头按钮：自带按下态（ui-active）与禁用态（ui-disabled）CSS 变体，样式完全自定义。"
      >
        <Button
          className="UiButton UiButton--primary"
          onClick={() => setResult('主要按钮被点击')}
        >
          <text className="UiButton__text UiButton__text--primary">
            {t('主要按钮')}
          </text>
        </Button>
        <Button
          className="UiButton UiButton--default"
          onClick={() => setResult('次要按钮被点击')}
        >
          <text className="UiButton__text">{t('次要按钮')}</text>
        </Button>
        <Button
          className="UiButton UiButton--warn"
          onClick={() => setResult('警示操作被点击')}
        >
          <text className="UiButton__text UiButton__text--warn">
            {t('警示操作')}
          </text>
        </Button>
        <Button className="UiButton UiButton--default" disabled>
          <text className="UiButton__text UiButton__text--disabled">
            {t('禁用状态')}
          </text>
        </Button>
        <ResultLine text={result} placeholder="点击任意按钮查看事件" />
      </DemoCard>
    </view>
  );
}

export function InputPage() {
  const [value, setValue] = useState('');
  const [multiline, setMultiline] = useState('');

  return (
    <view>
      <ApiName name="<Input />" />
      <DemoCard
        title="单行输入框"
        desc="受控输入：onInput 回传最新文本，可设置 placeholder。"
      >
        <Input
          className="UiInput"
          placeholder={t('请输入内容')}
          value={value}
          onInput={setValue}
        />
        <ResultLine
          text={value.length > 0 ? `已输入 ${value.length} 字：${value}` : null}
          placeholder="输入内容实时展示在这里"
        />
      </DemoCard>
      <DemoCard title="多行输入框" desc="TextArea 支持多行文本输入。">
        <TextArea
          className="UiTextArea"
          placeholder={t('写点什么…')}
          value={multiline}
          onInput={setMultiline}
        />
        <ResultLine
          text={multiline.length > 0 ? `已输入 ${multiline.length} 字` : null}
          placeholder="多行输入内容统计"
        />
      </DemoCard>
    </view>
  );
}

export function KeyboardPage() {
  const colorScheme = readColorScheme(useInitData());
  const keyboard = useKeyboard();
  const [name, setName] = useState('');
  const [notes, setNotes] = useState('');
  const [popupResult, setPopupResult] = useState<string | null>(null);

  const openKeyboardDialog = () => {
    setPopupResult(null);
    router
      .openForResult<{ message?: unknown }>({
        bundle: 'main',
        presentation: 'inputDialog',
        statusBarStyle:
          colorScheme === 'dark' ? 'light-content' : 'dark-content',
        params: { page: 'keyboard-input-dialog' },
      })
      .then((result) => {
        'background only';
        if (typeof result?.message === 'string') {
          setPopupResult(`已发送：${result.message}`);
        } else if (result === undefined) {
          setPopupResult('弹窗已取消');
        }
      })
      .catch((error: Error) => {
        'background only';
        setPopupResult(`打开失败：${error.message}`);
      });
  };

  return (
    <view>
      <ApiName name="useKeyboard()" />
      <DemoCard
        title="键盘状态"
        desc="useKeyboard() 将 keyboardstatuschanged 归一化为类型化的 visible 与 height。"
      >
        <view className="KeyboardDemo__metrics">
          <view className="KeyboardDemo__metric">
            <text className="KeyboardDemo__metricLabel">visible</text>
            <text className="KeyboardDemo__metricValue">
              {keyboard.visible ? 'true' : 'false'}
            </text>
          </view>
          <view className="KeyboardDemo__metric">
            <text className="KeyboardDemo__metricLabel">height</text>
            <text className="KeyboardDemo__metricValue">
              {keyboard.height}px
            </text>
          </view>
        </view>
      </DemoCard>

      <DemoCard
        title="页面中部输入框"
        desc="PageFrame 开启 keyboardAware；每个输入目标由 KeyboardAwareTrigger 标记。"
      >
        <KeyboardAwareTrigger offset={12}>
          <Input
            className="UiInput"
            placeholder={t('输入姓名')}
            value={name}
            onInput={setName}
          />
        </KeyboardAwareTrigger>
      </DemoCard>

      <DemoCard
        title="三端独立键盘弹窗"
        desc="inputDialog 使用独立原生覆盖层适配键盘，不会重排后面的页面。Android 固定 resize；点击空白或返回时，待键盘收起后再关闭。"
      >
        <DemoButton
          label="打开独立键盘弹窗"
          primary
          onTap={openKeyboardDialog}
        />
        <ResultLine text={popupResult} placeholder="发送结果会显示在这里" />
      </DemoCard>

      <DemoCard
        title="测试方式"
        desc="先观察上方状态，再滚动到页面底部并聚焦多行输入框。键盘弹出后，PageFrame 会自动滚动，避免输入框被遮挡。"
      >
        <view className="KeyboardDemo__steps">
          <text className="KeyboardDemo__step">{t('1　聚焦任意输入框')}</text>
          <text className="KeyboardDemo__step">
            {t('2　观察 visible 和 height')}
          </text>
          <text className="KeyboardDemo__step">
            {t('3　关闭键盘并确认页面复位')}
          </text>
        </view>
      </DemoCard>

      <DemoCard
        title="页面底部输入框"
        desc="这个输入框用于验证自动滚动与额外的 16px 避让距离。"
      >
        <KeyboardAwareTrigger offset={16}>
          <TextArea
            className="UiTextArea"
            placeholder={t('输入较长的备注…')}
            value={notes}
            onInput={setNotes}
          />
        </KeyboardAwareTrigger>
        <ResultLine
          text={notes.length > 0 ? `已输入 ${notes.length} 字` : null}
          placeholder="聚焦输入框后观察键盘避让效果"
        />
      </DemoCard>
    </view>
  );
}

/** Content rendered inside the platform-native inputDialog overlay. */
export function KeyboardInputDialogPage() {
  const [value, setValue] = useState('');
  const inputRef = useRef<InputRef>(null);
  const contentInsetBottom = useRouteContentInsetBottom();

  useEffect(() => {
    'background only';
    inputRef.current?.focus().catch(() => {
      // The route may have been dismissed before its first screen completed.
    });
  }, []);

  const close = () => {
    router.close().catch(() => {});
  };

  const send = () => {
    const message = value.trim();
    if (message.length === 0) return;
    router.closeWithResult({ message }).catch(() => {});
  };

  return (
    <view className="KeyboardInputDialog">
      <view
        className="KeyboardInputDialog__panel"
        style={{ paddingBottom: `${12 + contentInsetBottom}px` }}
      >
        <view className="KeyboardPopup__header">
          <text className="KeyboardPopup__title">{t('写一条评论')}</text>
          <view className="KeyboardPopup__close" bindtap={close}>
            <text className="KeyboardPopup__closeText">{t('取消')}</text>
          </view>
        </view>
        <view className="KeyboardPopup__row">
          <Input
            ref={inputRef}
            className="KeyboardPopup__input"
            placeholder={t('输入内容…')}
            value={value}
            confirmType="send"
            onInput={setValue}
            onConfirm={send}
          />
          <view
            className={`KeyboardPopup__send${
              value.trim().length === 0 ? ' KeyboardPopup__send--disabled' : ''
            }`}
            bindtap={send}
          >
            <text className="KeyboardPopup__sendText">{t('发送')}</text>
          </view>
        </view>
      </view>
    </view>
  );
}

function formatPercent(value: number): string {
  'background only';
  return `${Math.round(value * 100)}%`;
}

export function SliderPage() {
  const [value, setValue] = useState(0.6);
  const [stepValue, setStepValue] = useState(0.3);

  return (
    <view>
      <ApiName name="<SliderRoot />" />
      <DemoCard
        title="连续滑块"
        desc="拖动或点按轨道改变数值，主线程手势驱动，跟手不掉帧。"
      >
        <view className="SliderRow">
          <SliderRoot
            className="UiSlider"
            value={value}
            onValueChange={setValue}
          >
            <SliderTrack className="UiSlider__track">
              <SliderIndicator className="UiSlider__indicator" />
              <SliderThumb className="UiSlider__thumbWrap">
                <view className="UiSlider__thumb" />
              </SliderThumb>
            </SliderTrack>
          </SliderRoot>
          <text className="SliderRow__value">{formatPercent(value)}</text>
        </view>
      </DemoCard>
      <DemoCard title="禁用状态" desc="disabled 后滑块不再响应手势。">
        <view className="SliderRow">
          <SliderRoot
            className="UiSlider ui-disabled"
            defaultValue={stepValue}
            disabled
            onValueChange={setStepValue}
          >
            <SliderTrack className="UiSlider__track">
              <SliderIndicator className="UiSlider__indicator" />
              <SliderThumb className="UiSlider__thumbWrap">
                <view className="UiSlider__thumb" />
              </SliderThumb>
            </SliderTrack>
          </SliderRoot>
          <text className="SliderRow__value SliderRow__value--disabled">
            {formatPercent(stepValue)}
          </text>
        </view>
      </DemoCard>
    </view>
  );
}
