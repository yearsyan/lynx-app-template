import type { ReactNode } from '@lynx-js/react';

import {
  BatteryPage,
  BiometricPage,
  ClipboardPage,
  DeviceInfoPage,
  HapticsPage,
  ScannerPage,
  SensorsPage,
} from './api-device.js';
import { BrightnessPage, StatusBarPage, ToastPage } from './api-interface.js';
import { AlbumPage, ScreenshotPage, WebViewPage } from './api-media.js';
import { FetchPage, OpenUrlPage, WebSocketPage } from './api-network.js';
import { ActivitySheetPage } from './api-open.js';
import { FileSystemPage, KvPage, SecureStoragePage } from './api-storage.js';
import { ButtonPage, InputPage, SliderPage } from './ui-basic.js';
import {
  CheckboxPage,
  DropdownPage,
  RadioPage,
  SwitchPage,
} from './ui-choice.js';
import { DialogPage, SheetPage } from './ui-feedback.js';
import { SwiperPage } from './ui-view.js';

export interface DemoItemMeta {
  key: string;
  title: string;
  subtitle?: string;
}

export interface DemoCategoryMeta {
  key: string;
  title: string;
  /** Single CJK glyph: renders identically on Android, iOS and HarmonyOS. */
  glyph: string;
  tileBackground: string;
  tileColor: string;
  items: DemoItemMeta[];
}

export interface DemoTabMeta {
  key: 'api' | 'ui';
  label: string;
  /** Single CJK glyph for the hero tile. */
  glyph: string;
  headline: string;
  description: string;
  categories: [DemoCategoryMeta, ...DemoCategoryMeta[]];
}

export const TABS: [DemoTabMeta, DemoTabMeta] = [
  {
    key: 'api',
    label: '接口',
    glyph: '接',
    headline: 'Lynx 接口能力展示',
    description:
      '以下将演示 Lynx 跨端接口能力，具体属性参数详见 Lynx 开发文档。所有接口在 Android / iOS / HarmonyOS 三端行为一致。',
    categories: [
      {
        key: 'ui',
        title: '界面',
        glyph: '界',
        tileBackground: '#e7f6ec',
        tileColor: '#07c160',
        items: [
          { key: 'toast', title: 'Toast 提示' },
          { key: 'statusbar', title: '状态栏样式' },
          { key: 'brightness', title: '屏幕亮度' },
        ],
      },
      {
        key: 'device',
        title: '设备',
        glyph: '设',
        tileBackground: '#e8f0fe',
        tileColor: '#1a73e8',
        items: [
          { key: 'deviceinfo', title: '设备信息' },
          { key: 'battery', title: '电池电量' },
          { key: 'sensors', title: '传感器' },
          { key: 'biometric', title: '生物认证' },
          { key: 'clipboard', title: '剪贴板' },
          { key: 'haptics', title: '振动反馈' },
          { key: 'scanner', title: '扫码' },
        ],
      },
      {
        key: 'network',
        title: '网络',
        glyph: '网',
        tileBackground: '#e0f2f1',
        tileColor: '#00897b',
        items: [
          { key: 'fetch', title: '发起请求' },
          { key: 'websocket', title: 'WebSocket' },
          { key: 'openurl', title: '打开链接' },
        ],
      },
      {
        key: 'media',
        title: '媒体',
        glyph: '媒',
        tileBackground: '#fff3e0',
        tileColor: '#f57c00',
        items: [
          { key: 'screenshot', title: '截图' },
          { key: 'album', title: '相册' },
          { key: 'webview', title: 'WebView 桥' },
        ],
      },
      {
        key: 'storage',
        title: '数据',
        glyph: '数',
        tileBackground: '#f3e5f5',
        tileColor: '#8e24aa',
        items: [
          { key: 'kv', title: 'MMKV 存储' },
          { key: 'secure', title: '安全存储' },
          { key: 'fs', title: '文件系统' },
        ],
      },
      {
        key: 'open',
        title: '开放接口',
        glyph: '开',
        tileBackground: '#ffebee',
        tileColor: '#e53935',
        items: [{ key: 'sheet', title: '半透明堆叠页' }],
      },
    ],
  },
  {
    key: 'ui',
    label: '组件',
    glyph: '组',
    headline: 'Lynx UI 组件展示',
    description:
      '以下组件来自官方无头组件库 @lynx-js/lynx-ui，iOS 上部分控件直接渲染原生 Liquid Glass 元素。',
    categories: [
      {
        key: 'basic',
        title: '基础组件',
        glyph: '基',
        tileBackground: '#e3f2fd',
        tileColor: '#1e88e5',
        items: [
          { key: 'button', title: '按钮 Button' },
          { key: 'input', title: '输入框 Input' },
          { key: 'slider', title: '滑块 Slider' },
        ],
      },
      {
        key: 'choice',
        title: '选择控件',
        glyph: '选',
        tileBackground: '#e8f5e9',
        tileColor: '#43a047',
        items: [
          { key: 'switch', title: '开关 Switch' },
          { key: 'checkbox', title: '多选 Checkbox' },
          { key: 'radio', title: '单选 Radio' },
          { key: 'dropdown', title: '下拉 Dropdown' },
        ],
      },
      {
        key: 'feedback',
        title: '反馈组件',
        glyph: '反',
        tileBackground: '#fff8e1',
        tileColor: '#f9a825',
        items: [
          { key: 'dialog', title: '对话框 Dialog' },
          { key: 'actionsheet', title: '底部弹层 Sheet' },
        ],
      },
      {
        key: 'view',
        title: '视图组件',
        glyph: '视',
        tileBackground: '#fce4ec',
        tileColor: '#d81b60',
        items: [{ key: 'swiper', title: '轮播 Swiper' }],
      },
    ],
  },
];

interface DemoPageEntry {
  title: string;
  render: () => ReactNode;
}

export const PAGES: Record<string, DemoPageEntry> = {
  toast: { title: 'Toast 提示', render: () => <ToastPage /> },
  statusbar: { title: '状态栏样式', render: () => <StatusBarPage /> },
  brightness: { title: '屏幕亮度', render: () => <BrightnessPage /> },
  deviceinfo: { title: '设备信息', render: () => <DeviceInfoPage /> },
  battery: { title: '电池电量', render: () => <BatteryPage /> },
  sensors: { title: '传感器', render: () => <SensorsPage /> },
  biometric: { title: '生物认证', render: () => <BiometricPage /> },
  clipboard: { title: '剪贴板', render: () => <ClipboardPage /> },
  haptics: { title: '振动反馈', render: () => <HapticsPage /> },
  scanner: { title: '扫码', render: () => <ScannerPage /> },
  fetch: { title: '发起请求', render: () => <FetchPage /> },
  websocket: { title: 'WebSocket', render: () => <WebSocketPage /> },
  openurl: { title: '打开链接', render: () => <OpenUrlPage /> },
  screenshot: { title: '截图', render: () => <ScreenshotPage /> },
  album: { title: '相册', render: () => <AlbumPage /> },
  webview: { title: 'WebView 桥', render: () => <WebViewPage /> },
  kv: { title: 'MMKV 存储', render: () => <KvPage /> },
  secure: { title: '安全存储', render: () => <SecureStoragePage /> },
  fs: { title: '文件系统', render: () => <FileSystemPage /> },
  sheet: { title: '半透明堆叠页', render: () => <ActivitySheetPage /> },
  button: { title: '按钮', render: () => <ButtonPage /> },
  input: { title: '输入框', render: () => <InputPage /> },
  slider: { title: '滑块', render: () => <SliderPage /> },
  switch: { title: '开关', render: () => <SwitchPage /> },
  checkbox: { title: '多选框', render: () => <CheckboxPage /> },
  radio: { title: '单选框', render: () => <RadioPage /> },
  dropdown: { title: '下拉', render: () => <DropdownPage /> },
  dialog: { title: '对话框', render: () => <DialogPage /> },
  actionsheet: { title: '底部弹层', render: () => <SheetPage /> },
  swiper: { title: '轮播', render: () => <SwiperPage /> },
};
