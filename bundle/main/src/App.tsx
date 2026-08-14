// organizeImports is disabled for this file in biome.json: the scaffolder
// rewrites the workspace scope below (@lynx-template -> @<user scope>), which
// changes the sort order relative to the @lynx-js/* imports.
import { nativeKV } from '@lynx-template/native-bridge';

import { useCallback, useEffect, useState } from '@lynx-js/react';

import './App.css';
import { PlatformDropdown } from './components/PlatformDropdown.js';
import { PlatformSwitch } from './components/PlatformSwitch.js';

const COUNTER_KEY = 'template.counter';
const FRUITS = ['Apple', 'Banana', 'Cherry', 'Durian', 'Elderberry'];
const isIOS = SystemInfo.platform.toLowerCase() === 'ios';

export function App() {
  const [count, setCount] = useState(0);
  const [savedCount, setSavedCount] = useState<string | null>(null);
  const [status, setStatus] = useState('Ready');
  const [notificationsOn, setNotificationsOn] = useState(true);
  const [fruitIndex, setFruitIndex] = useState(-1);

  useEffect(() => {
    console.info(
      `Lynx Template · ${SystemInfo.platform} · engine ${SystemInfo.engineVersion}`,
    );
  }, []);

  const increment = useCallback(() => {
    'background only';
    setCount((current) => current + 1);
  }, []);

  const reset = useCallback(() => {
    'background only';
    setCount(0);
  }, []);

  const saveToMMKV = useCallback(() => {
    'background only';
    nativeKV
      .setString(COUNTER_KEY, String(Date.now()))
      .then(() => nativeKV.getString(COUNTER_KEY))
      .then((value) => {
        setSavedCount(value);
        setStatus('Saved to MMKV');
      })
      .catch((error: Error) => setStatus(error.message));
  }, []);

  const readFromMMKV = useCallback(() => {
    'background only';
    nativeKV
      .getString(COUNTER_KEY)
      .then((value) => {
        setSavedCount(value);
        setStatus(value === null ? 'MMKV is empty' : 'Read from MMKV');
      })
      .catch((error: Error) => setStatus(error.message));
  }, []);

  const handleSwitchChange = useCallback((value: boolean) => {
    'background only';
    setNotificationsOn(value);
    setStatus(`Switch ${value ? 'on' : 'off'}`);
  }, []);

  const handleFruitSelect = useCallback((index: number, value: string) => {
    'background only';
    setFruitIndex(index);
    setStatus(`Picked ${value} (#${index})`);
  }, []);

  return (
    <view className="App">
      <view className="Header">
        <text className="Title">Lynx Template</text>
        <text className="Subtitle">
          {SystemInfo.platform} · engine {SystemInfo.engineVersion}
          {isIOS ? ' · Liquid Glass' : ' · Lynx fallback'}
        </text>
      </view>

      <view className="Card">
        <text className="CardTitle">Switch</text>
        <view className="FieldRow">
          <text className="FieldLabel">Enable notifications</text>
          <PlatformSwitch
            checked={notificationsOn}
            onChange={handleSwitchChange}
          />
        </view>
        <view className="FieldRow">
          <text className="FieldLabel">Disabled switch</text>
          <PlatformSwitch checked={false} disabled={true} onChange={() => {}} />
        </view>
      </view>

      <view className="Card">
        <text className="CardTitle">Dropdown</text>
        <PlatformDropdown
          title="Pick a fruit"
          options={FRUITS}
          selected={fruitIndex}
          onSelect={handleFruitSelect}
        />
        <text className="CardBody">
          {fruitIndex >= 0 ? `Selected: ${FRUITS[fruitIndex]}` : 'No selection'}
        </text>
      </view>

      <view className="Card">
        <text className="CardTitle">Tap counter</text>
        <text className="Counter">{count}</text>
        <view className="Row">
          <view className="Button Button--primary" bindtap={increment}>
            <text className="ButtonLabel ButtonLabel--primary">+1</text>
          </view>
          <view className="Button" bindtap={reset}>
            <text className="ButtonLabel">Reset</text>
          </view>
        </view>
      </view>

      <view className="Card">
        <text className="CardTitle">Native MMKV</text>
        <text className="CardBody">
          {savedCount === null ? 'Nothing loaded yet' : `Stored: ${savedCount}`}
        </text>
        <view className="Row">
          <view className="Button Button--primary" bindtap={saveToMMKV}>
            <text className="ButtonLabel ButtonLabel--primary">Save</text>
          </view>
          <view className="Button" bindtap={readFromMMKV}>
            <text className="ButtonLabel">Read</text>
          </view>
        </view>
      </view>

      <text className="Status">{status}</text>
    </view>
  );
}
