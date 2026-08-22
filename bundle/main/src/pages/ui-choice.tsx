import {
  Checkbox,
  CheckboxIndicator,
  Radio,
  RadioGroupRoot,
  RadioIndicator,
  Switch,
  SwitchThumb,
  SwitchTrack,
} from '@lynx-js/lynx-ui';
import { useState } from '@lynx-js/react';

import { ApiName, DemoCard, ResultLine } from '../components/Demo.js';
import { PlatformDropdown } from '../components/PlatformDropdown.js';
import { PlatformSwitch } from '../components/PlatformSwitch.js';

const isIOS = SystemInfo.platform.toLowerCase() === 'ios';

export function SwitchPage() {
  const [checked, setChecked] = useState(true);
  const [nativeChecked, setNativeChecked] = useState(false);

  return (
    <view>
      <ApiName name="<Switch />" />
      <DemoCard
        title="Lynx UI 开关"
        desc="无头开关组件：轨道与滑块自由布局，ui-checked / ui-active 变体驱动过渡动画。"
      >
        <view className="ChoiceRow">
          <Switch className="UiSwitch" checked={checked} onChange={setChecked}>
            <SwitchTrack className="UiSwitch__track" />
            <SwitchThumb className="UiSwitch__thumb" />
          </Switch>
          <text className="ChoiceRow__label">
            {checked ? '已开启' : '已关闭'}
          </text>
        </view>
        <view className="ChoiceRow">
          <Switch className="UiSwitch ui-disabled" disabled defaultChecked>
            <SwitchTrack className="UiSwitch__track" />
            <SwitchThumb className="UiSwitch__thumb" />
          </Switch>
          <text className="ChoiceRow__label ChoiceRow__label--disabled">
            禁用状态
          </text>
        </view>
      </DemoCard>
      <DemoCard
        title={isIOS ? '原生 Liquid Glass 开关' : '平台开关'}
        desc={
          isIOS
            ? 'iOS 直接渲染原生 Liquid Glass UISwitch，触感与动画与系统完全一致。'
            : '当前平台使用 Lynx 绘制的回退开关；在 iOS 上会替换为原生 Liquid Glass 控件。'
        }
      >
        <view className="ChoiceRow">
          <PlatformSwitch checked={nativeChecked} onChange={setNativeChecked} />
          <text className="ChoiceRow__label">
            {nativeChecked ? '已开启' : '已关闭'}
          </text>
        </view>
      </DemoCard>
    </view>
  );
}

const CHECK_ITEMS = ['微信', '支付宝', '云闪付'];

export function CheckboxPage() {
  const [selected, setSelected] = useState<string[]>(['微信']);

  const toggle = (item: string, value: boolean) => {
    'background only';
    setSelected((current) =>
      value ? [...current, item] : current.filter((name) => name !== item),
    );
  };

  return (
    <view>
      <ApiName name="<Checkbox />" />
      <DemoCard
        title="多选框"
        desc="无头多选组件，指示器内容完全自定义；这里绘制了一个绿色对勾。"
      >
        {CHECK_ITEMS.map((item) => (
          <view key={item} className="ChoiceRow">
            <Checkbox
              className="UiCheckbox"
              checked={selected.includes(item)}
              onChange={(value) => toggle(item, value)}
            >
              <CheckboxIndicator className="UiCheckbox__indicator">
                <text className="UiCheckbox__mark">✓</text>
              </CheckboxIndicator>
            </Checkbox>
            <text className="ChoiceRow__label">{item}</text>
          </view>
        ))}
        <ResultLine
          text={selected.length > 0 ? `已选择：${selected.join('、')}` : null}
          placeholder="尚未选择任何支付方式"
        />
      </DemoCard>
    </view>
  );
}

const RADIO_ITEMS = ['标准模式', '长辈模式', '青少年模式'];

export function RadioPage() {
  const [value, setValue] = useState(RADIO_ITEMS[0]);

  return (
    <view>
      <ApiName name="<RadioGroupRoot />" />
      <DemoCard
        title="单选框"
        desc="RadioGroupRoot 管理整组选中值，Radio + RadioIndicator 组成单个选项。"
      >
        <RadioGroupRoot value={value} onValueChange={setValue}>
          {RADIO_ITEMS.map((item) => (
            <view key={item} className="ChoiceRow">
              <Radio className="UiRadio" value={item}>
                <RadioIndicator className="UiRadio__indicator">
                  <view className="UiRadio__dot" />
                </RadioIndicator>
              </Radio>
              <text className="ChoiceRow__label">{item}</text>
            </view>
          ))}
        </RadioGroupRoot>
        <ResultLine text={`当前：${value}`} placeholder="请选择一个模式" />
      </DemoCard>
    </view>
  );
}

const FRUITS = ['苹果', '香蕉', '樱桃', '榴莲', '蓝莓'];

export function DropdownPage() {
  const [index, setIndex] = useState(-1);

  return (
    <view>
      <ApiName name="<PlatformDropdown />" />
      <DemoCard
        title="平台下拉"
        desc={
          isIOS
            ? '按钮和选中态由 Lynx 绘制；点击时由 iOS 原生 UIMenu 呈现 Liquid Glass 菜单。'
            : '按钮、选中态和弹层均由 Lynx 绘制。'
        }
      >
        <view className="GlassStage">
          <PlatformDropdown
            title="选择一种水果"
            options={FRUITS}
            selected={index}
            onSelect={(next) => setIndex(next)}
          />
          {isIOS ? (
            <text className="GlassStage__hint">
              点击 Lynx 按钮打开原生 Liquid Glass 菜单
            </text>
          ) : null}
        </view>
        <ResultLine
          text={
            index >= 0 ? `已选择：${FRUITS[index]}（第 ${index + 1} 项）` : null
          }
          placeholder="尚未选择"
        />
      </DemoCard>
    </view>
  );
}
