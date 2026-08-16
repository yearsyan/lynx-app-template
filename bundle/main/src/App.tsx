// organizeImports is disabled for this file in biome.json: the scaffolder
// rewrites the workspace scope below (@lynx-template -> @<user scope>), which
// changes the sort order relative to the @lynx-js/* imports.
import {
  nativeClipboard,
  nativeHaptics,
  nativeKV,
  nativeStatusBar,
} from '@lynx-template/native-bridge';
import { openActivityBottomSheet } from '@lynx-template/activity-sheet';

import { useCallback, useEffect, useState } from '@lynx-js/react';

import './App.css';
import { PlatformDropdown } from './components/PlatformDropdown.js';
import { PlatformSwitch } from './components/PlatformSwitch.js';
import { platformToast, ToastHost } from './components/PlatformToast.js';

const COUNTER_KEY = 'template.counter';
const FRUITS = ['Apple', 'Banana', 'Cherry', 'Durian', 'Elderberry'];
const MAX_DEMO_LAYERS = 3;
const isIOS = SystemInfo.platform.toLowerCase() === 'ios';

export function App() {
  const [count, setCount] = useState(0);
  const [savedCount, setSavedCount] = useState<string | null>(null);
  const [clipText, setClipText] = useState<string | null>(null);
  const [status, setStatus] = useState('Ready');
  const [notificationsOn, setNotificationsOn] = useState(true);
  const [fruitIndex, setFruitIndex] = useState(-1);

  useEffect(() => {
    'background only';
    console.info(
      `Lynx Template · ${SystemInfo.platform} · engine ${SystemInfo.engineVersion}`,
    );
    nativeStatusBar
      .setStyle('dark-content')
      .catch((error: Error) => setStatus(error.message));
  }, []);

  const increment = useCallback(() => {
    'background only';
    setCount((current) => current + 1);
    nativeHaptics.impact('medium').catch(() => {});
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
        platformToast.success('Saved to MMKV');
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

  const saveToClipboard = useCallback(() => {
    'background only';
    const value = `clip-${Date.now()}`;
    nativeClipboard
      .setString(value)
      .then(() => {
        setClipText(value);
        setStatus('Saved to clipboard');
        platformToast.success('Copied to clipboard');
      })
      .catch((error: Error) => setStatus(error.message));
  }, []);

  const readFromClipboard = useCallback(() => {
    'background only';
    nativeClipboard
      .getString()
      .then((value) => {
        setClipText(value);
        setStatus(
          value === null ? 'Clipboard is empty' : 'Read from clipboard',
        );
      })
      .catch((error: Error) => setStatus(error.message));
  }, []);

  const handleSwitchChange = useCallback((value: boolean) => {
    'background only';
    setNotificationsOn(value);
    setStatus(`Switch ${value ? 'on' : 'off'}`);
    nativeHaptics.impact('light').catch(() => {});
  }, []);

  const handleFruitSelect = useCallback((index: number, value: string) => {
    'background only';
    setFruitIndex(index);
    setStatus(`Picked ${value} (#${index})`);
    platformToast.info(`Picked ${value}`);
  }, []);

  const openPredictiveBackDemo = useCallback(() => {
    'background only';
    setStatus('Opening transparent Activity sheet…');
    openActivityBottomSheet({
      bundle: 'predictive-back-sheet',
      statusBarStyle: 'dark-content',
      params: { level: 1, maxDepth: MAX_DEMO_LAYERS },
    })
      .then(() => setStatus('Transparent Activity sheet opened'))
      .catch((error: Error) => setStatus(error.message));
  }, []);

  return (
    <view className="AppRoot">
      <scroll-view
        className="AppScroll"
        scroll-orientation="vertical"
        scroll-bar-enable={false}
      >
        <view className="App">
          <view className="Header">
            <text className="Title">Lynx Template</text>
            <text className="Subtitle">
              {SystemInfo.platform} · engine {SystemInfo.engineVersion}
              {isIOS ? ' · Liquid Glass' : ' · Lynx fallback'}
            </text>
          </view>

          <view className="Card PredictiveBackCard">
            <text className="CardTitle">Predictive back stack</text>
            <text className="CardBody PredictiveBackCard__body">
              Open a full-width bottom sheet in a transparent Activity, then
              push up to three native layers. Back moves only the top sheet
              downward.
            </text>
            <view
              className="Button Button--primary PredictiveBackCard__button"
              bindtap={openPredictiveBackDemo}
            >
              <text className="ButtonLabel ButtonLabel--primary">
                Open stack demo
              </text>
            </view>
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
              <PlatformSwitch
                checked={false}
                disabled={true}
                onChange={() => {}}
              />
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
              {fruitIndex >= 0
                ? `Selected: ${FRUITS[fruitIndex]}`
                : 'No selection'}
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
              {savedCount === null
                ? 'Nothing loaded yet'
                : `Stored: ${savedCount}`}
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

          <view className="Card">
            <text className="CardTitle">Clipboard</text>
            <text className="CardBody">
              {clipText === null ? 'Nothing copied yet' : `Copied: ${clipText}`}
            </text>
            <view className="Row">
              <view
                className="Button Button--primary"
                bindtap={saveToClipboard}
              >
                <text className="ButtonLabel ButtonLabel--primary">Copy</text>
              </view>
              <view className="Button" bindtap={readFromClipboard}>
                <text className="ButtonLabel">Read</text>
              </view>
            </view>
          </view>

          <text className="Status">{status}</text>
        </view>
      </scroll-view>
      <ToastHost />
    </view>
  );
}
