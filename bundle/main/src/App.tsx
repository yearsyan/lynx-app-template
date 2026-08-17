// organizeImports is disabled for this file in biome.json: the scaffolder
// rewrites the workspace scope below (@lynx-template -> @<user scope>), which
// changes the sort order relative to the @lynx-js/* imports.
import {
  biometric,
  clipboard,
  deviceInfo,
  display,
  haptics,
  kv,
  router,
  screenshot,
  statusBar,
  toast,
} from '@lynx-app/native-bridge';
import { openActivityBottomSheet } from '@lynx-template/activity-sheet';

import { useCallback, useEffect, useState } from '@lynx-js/react';

import './App.css';
import { PlatformDropdown } from './components/PlatformDropdown.js';
import { PlatformSwitch } from './components/PlatformSwitch.js';

const COUNTER_KEY = 'template.counter';
const FRUITS = ['Apple', 'Banana', 'Cherry', 'Durian', 'Elderberry'];
const MAX_DEMO_LAYERS = 3;
const isIOS = SystemInfo.platform.toLowerCase() === 'ios';

// `idSelector` is a standard Lynx element attribute that the native
// screenshot lookups (LynxView.findViewByIdSelector / viewWithIdSelector:)
// resolve against; react-lynx's prop typings do not declare it yet.
const screenshotCardSelector: Record<string, string> = {
  idSelector: 'screenshot-card',
};

/** Standard Base64 of 16 random bytes, standing in for a server nonce. */
function randomDemoChallenge(): string {
  const bytes = new Uint8Array(16);
  for (let i = 0; i < bytes.length; i += 1) {
    bytes[i] = Math.floor(Math.random() * 256);
  }
  let binary = '';
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return binaryToBase64(binary);
}

/** Minimal Base64 encoder (the Lynx runtime has no atob/btoa). */
function binaryToBase64(binary: string): string {
  const alphabet =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  let output = '';
  for (let i = 0; i < binary.length; i += 3) {
    const a = binary.charCodeAt(i);
    const b = binary.charCodeAt(i + 1);
    const c = binary.charCodeAt(i + 2);
    output += alphabet[a >> 2];
    output += alphabet[((a & 3) << 4) | (Number.isNaN(b) ? 0 : b >> 4)];
    const second = Number.isNaN(b) ? 64 : ((b & 15) << 2) | (c >> 6);
    output += second === 64 ? '=' : alphabet[second];
    output += Number.isNaN(c) ? '=' : alphabet[c & 63];
  }
  return output;
}

export function App() {
  const [count, setCount] = useState(0);
  const [savedCount, setSavedCount] = useState<string | null>(null);
  const [clipText, setClipText] = useState<string | null>(null);
  const [shotSummary, setShotSummary] = useState<string | null>(null);
  const [biometricSummary, setBiometricSummary] = useState<string | null>(null);
  const [deviceSummary, setDeviceSummary] = useState<string | null>(null);
  const [status, setStatus] = useState('Ready');
  const [notificationsOn, setNotificationsOn] = useState(true);
  const [fruitIndex, setFruitIndex] = useState(-1);

  useEffect(() => {
    'background only';
    console.info(
      `Lynx Template · ${SystemInfo.platform} · engine ${SystemInfo.engineVersion}`,
    );
    statusBar
      .setStyle('dark-content')
      .catch((error: Error) => setStatus(error.message));
  }, []);

  const increment = useCallback(() => {
    'background only';
    setCount((current) => current + 1);
    haptics.impact('medium').catch(() => {});
  }, []);

  const reset = useCallback(() => {
    'background only';
    setCount(0);
  }, []);

  const saveToMMKV = useCallback(() => {
    'background only';
    kv.setString(COUNTER_KEY, String(Date.now()))
      .then(() => kv.getString(COUNTER_KEY))
      .then((value) => {
        setSavedCount(value);
        setStatus('Saved to MMKV');
        toast.success('Saved to MMKV').catch(() => {});
      })
      .catch((error: Error) => setStatus(error.message));
  }, []);

  const readFromMMKV = useCallback(() => {
    'background only';
    kv.getString(COUNTER_KEY)
      .then((value) => {
        setSavedCount(value);
        setStatus(value === null ? 'MMKV is empty' : 'Read from MMKV');
      })
      .catch((error: Error) => setStatus(error.message));
  }, []);

  const saveToClipboard = useCallback(() => {
    'background only';
    const value = `clip-${Date.now()}`;
    clipboard
      .setString(value)
      .then(() => {
        setClipText(value);
        setStatus('Saved to clipboard');
        toast.success('Copied to clipboard').catch(() => {});
      })
      .catch((error: Error) => setStatus(error.message));
  }, []);

  const readFromClipboard = useCallback(() => {
    'background only';
    clipboard
      .getString()
      .then((value) => {
        setClipText(value);
        setStatus(
          value === null ? 'Clipboard is empty' : 'Read from clipboard',
        );
      })
      .catch((error: Error) => setStatus(error.message));
  }, []);

  const checkBiometric = useCallback(() => {
    'background only';
    biometric
      .checkSupport()
      .then((support) => {
        setBiometricSummary(
          `${support.canAuthenticate ? 'Ready' : 'Unavailable'} · ` +
            `${support.biometryType} · ${support.reason} · ` +
            `credential ${support.deviceCredentialSetup ? 'set' : 'missing'}`,
        );
        setStatus(
          `Biometric ${support.canAuthenticate ? 'available' : support.reason}`,
        );
      })
      .catch((error: Error) => setStatus(error.message));
  }, []);

  const runBiometric = useCallback(() => {
    'background only';
    setStatus('Waiting for the system biometric prompt…');
    biometric
      .authenticate({
        title: 'Lynx Template',
        reason: 'Confirm your identity with biometrics.',
      })
      .then((outcome) => {
        const label = outcome.success ? 'Authenticated' : outcome.code;
        setBiometricSummary(label);
        setStatus(`Biometric: ${label}`);
      })
      .catch((error: Error) => setStatus(error.message));
  }, []);

  const makeSigningKey = useCallback(() => {
    'background only';
    setStatus('Generating the hardware signing key…');
    biometric
      .createSigningKey()
      .then((result) => {
        // In a real app the server receives this public key and binds it
        // to the account; verifiers use it for signChallenge signatures.
        setBiometricSummary(
          result.success
            ? `Key ${result.publicKey?.slice(0, 16)}…`
            : result.code,
        );
        setStatus(
          result.success
            ? 'Signing key created'
            : `Signing key: ${result.code}`,
        );
      })
      .catch((error: Error) => setStatus(error.message));
  }, []);

  const runSigningDemo = useCallback(() => {
    'background only';
    setStatus('Signing a local demo challenge…');
    // A real flow asks the server for a one-time nonce; signing it proves
    // to the server that a biometric prompt passed on this device.
    const challenge = randomDemoChallenge();
    biometric
      .signChallenge({
        challenge,
        title: 'Lynx Template',
        reason: 'Sign the demo challenge with biometrics.',
      })
      .then((result) => {
        setBiometricSummary(
          result.success
            ? `Signature ${result.signature?.slice(0, 16)}…`
            : result.code,
        );
        setStatus(
          result.success ? 'Challenge signed' : `Signing: ${result.code}`,
        );
      })
      .catch((error: Error) => setStatus(error.message));
  }, []);

  // The system resolves the scheme: `lynxapp://main` is registered by this
  // app itself, while any installed app can own the scheme instead
  // (`weixin://`, `imeituan://`, `alipay://…`, `https://…`).
  const openSystemURL = useCallback(() => {
    'background only';
    router
      .openURL('lynxapp://main')
      .then(() => setStatus('Opened lynxapp://main'))
      .catch((error: Error) => setStatus(error.message));
  }, []);

  const readDeviceInfo = useCallback(() => {
    'background only';
    Promise.all([
      deviceInfo.getInfo(),
      display.screenWidth(),
      display.windowWidth(),
      display.lynxViewWidth(),
    ])
      .then(([info, screen, windowWidth, view]) => {
        const traits = [
          info.isTablet ? 'tablet' : '',
          info.isFoldable ? 'foldable' : '',
        ]
          .filter((trait) => trait.length > 0)
          .join(' · ');
        setDeviceSummary(
          `${info.manufacturer} ${info.model} · OS ${info.osVersion} · ` +
            `v${info.appVersion} (${info.appBuild}) · ${info.density}x · ` +
            `${info.locale}${traits.length > 0 ? ` · ${traits}` : ''}`,
        );
        setStatus(
          `Width screen ${Math.round(screen)} / window ${Math.round(windowWidth)} / view ${Math.round(view)}`,
        );
      })
      .catch((error: Error) => setStatus(error.message));
  }, []);

  const summarizeShot = (
    label: string,
    result: { uri: string; width: number; height: number },
  ): string =>
    `${label}: ${Math.round(result.width)}x${Math.round(result.height)} · ${
      result.uri.split('/').pop() ?? result.uri
    }`;

  const captureCard = useCallback(() => {
    'background only';
    screenshot
      .capture({
        idSelector: 'screenshot-card',
        format: 'jpeg',
        quality: 90,
        fileName: 'demo-card',
      })
      .then((result) => {
        setShotSummary(summarizeShot('Card', result));
        setStatus('Captured card to cache');
      })
      .catch((error: Error) => setStatus(error.message));
  }, []);

  const captureView = useCallback(() => {
    'background only';
    screenshot
      .capture({ format: 'png' })
      .then((result) => {
        setShotSummary(summarizeShot('View', result));
        setStatus('Captured LynxView to cache');
      })
      .catch((error: Error) => setStatus(error.message));
  }, []);

  const capturePage = useCallback(() => {
    'background only';
    screenshot
      .capturePage({ format: 'png' })
      .then((result) => {
        setShotSummary(summarizeShot('Page', result));
        setStatus('Captured page to cache');
      })
      .catch((error: Error) => setStatus(error.message));
  }, []);

  const handleSwitchChange = useCallback((value: boolean) => {
    'background only';
    setNotificationsOn(value);
    setStatus(`Switch ${value ? 'on' : 'off'}`);
    haptics.impact('light').catch(() => {});
  }, []);

  const handleFruitSelect = useCallback((index: number, value: string) => {
    'background only';
    setFruitIndex(index);
    setStatus(`Picked ${value} (#${index})`);
    toast.info(`Picked ${value}`).catch(() => {});
  }, []);

  const showInfoToast = useCallback(() => {
    'background only';
    toast.info('Default in-window toast').catch(() => {});
  }, []);

  const showSuccessToast = useCallback(() => {
    'background only';
    toast.success('Saved successfully').catch(() => {});
  }, []);

  const showCustomToast = useCallback(() => {
    'background only';
    toast
      .show('Custom color, no icon', {
        backgroundColor: '#FF6750A4',
        showIcon: false,
        durationMs: 3000,
      })
      .catch(() => {});
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

          <view className="Card" {...screenshotCardSelector}>
            <text className="CardTitle">Screenshot</text>
            <text className="CardBody">
              {shotSummary === null
                ? 'Capture this card, the whole LynxView, or the native page as PNG/JPEG into the app cache.'
                : shotSummary}
            </text>
            <view className="Row">
              <view className="Button" bindtap={captureCard}>
                <text className="ButtonLabel">Card</text>
              </view>
              <view className="Button" bindtap={captureView}>
                <text className="ButtonLabel">View</text>
              </view>
              <view className="Button Button--primary" bindtap={capturePage}>
                <text className="ButtonLabel ButtonLabel--primary">Page</text>
              </view>
            </view>
          </view>

          <view className="Card">
            <text className="CardTitle">Toast</text>
            <text className="CardBody">
              In-window native toast: custom colors, optional icon, works
              without notification permission.
            </text>
            <view className="Row">
              <view className="Button" bindtap={showInfoToast}>
                <text className="ButtonLabel">Info</text>
              </view>
              <view className="Button" bindtap={showSuccessToast}>
                <text className="ButtonLabel">Success</text>
              </view>
              <view
                className="Button Button--primary"
                bindtap={showCustomToast}
              >
                <text className="ButtonLabel ButtonLabel--primary">Custom</text>
              </view>
            </view>
          </view>

          <view className="Card">
            <text className="CardTitle">Biometric</text>
            <text className="CardBody">
              {biometricSummary === null
                ? 'Silent capability check, system fingerprint / face prompt, and a hardware-bound signing key.'
                : biometricSummary}
            </text>
            <view className="Row">
              <view className="Button" bindtap={checkBiometric}>
                <text className="ButtonLabel">Check</text>
              </view>
              <view className="Button Button--primary" bindtap={runBiometric}>
                <text className="ButtonLabel ButtonLabel--primary">Verify</text>
              </view>
            </view>
            <view className="Row">
              <view className="Button" bindtap={makeSigningKey}>
                <text className="ButtonLabel">Make key</text>
              </view>
              <view className="Button Button--primary" bindtap={runSigningDemo}>
                <text className="ButtonLabel ButtonLabel--primary">Sign</text>
              </view>
            </view>
          </view>

          <view className="Card">
            <text className="CardTitle">System URL</text>
            <text className="CardBody">
              Opens lynxapp://main through the system router; any app that
              registered the scheme can handle it.
            </text>
            <view className="Row">
              <view className="Button Button--primary" bindtap={openSystemURL}>
                <text className="ButtonLabel ButtonLabel--primary">
                  Open URL
                </text>
              </view>
            </view>
          </view>

          <view className="Card">
            <text className="CardTitle">Device &amp; display</text>
            <text className="CardBody">
              {deviceSummary === null
                ? 'Model, OS, app version, density, locale and widths.'
                : deviceSummary}
            </text>
            <view className="Row">
              <view className="Button Button--primary" bindtap={readDeviceInfo}>
                <text className="ButtonLabel ButtonLabel--primary">Read</text>
              </view>
            </view>
          </view>

          <text className="Status">{status}</text>
        </view>
      </scroll-view>
    </view>
  );
}
