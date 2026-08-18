import {
  Button,
  Input,
  SliderIndicator,
  SliderRoot,
  SliderThumb,
  SliderTrack,
  TextArea,
} from '@lynx-js/lynx-ui';
import { useState } from '@lynx-js/react';

import { ApiName, DemoCard, ResultLine } from '../components/Demo.js';

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
            主要按钮
          </text>
        </Button>
        <Button
          className="UiButton UiButton--default"
          onClick={() => setResult('次要按钮被点击')}
        >
          <text className="UiButton__text">次要按钮</text>
        </Button>
        <Button
          className="UiButton UiButton--warn"
          onClick={() => setResult('警示操作被点击')}
        >
          <text className="UiButton__text UiButton__text--warn">警示操作</text>
        </Button>
        <Button className="UiButton UiButton--default" disabled>
          <text className="UiButton__text UiButton__text--disabled">
            禁用状态
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
          placeholder="请输入内容"
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
          placeholder="写点什么…"
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
