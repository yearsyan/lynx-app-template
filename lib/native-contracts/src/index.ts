// Generated from per-package NativeModule declarations. Do not edit.
// Run `pnpm native:contracts:generate` after changing a declaration.

import type { BackModule, StatusBarModule } from '@lynx-app/native-host/raw';
import type { AlbumUtilsModule } from '@lynx-template/autolink-album-utils/raw';
import type { AudioPlayerModule } from '@lynx-template/autolink-audio-player/raw';
import type { BatteryModule } from '@lynx-template/autolink-battery/raw';
import type { BiometricModule } from '@lynx-template/autolink-biometric/raw';
import type { ClipboardModule } from '@lynx-template/autolink-clipboard/raw';
import type { DeviceInfoModule } from '@lynx-template/autolink-device-info/raw';
import type { DisplayModule } from '@lynx-template/autolink-display/raw';
import type { FileSystemModule } from '@lynx-template/autolink-file-system/raw';
import type { HapticsModule } from '@lynx-template/autolink-haptics/raw';
import type { LocalNotificationModule } from '@lynx-template/autolink-local-notification/raw';
import type { KVModule } from '@lynx-template/autolink-mmkv/raw';
import type { PermissionsModule } from '@lynx-template/autolink-permissions/raw';
import type { RouterModule } from '@lynx-template/autolink-router/raw';
import type { ScannerModule } from '@lynx-template/autolink-scanner/raw';
import type { ScreenshotModule } from '@lynx-template/autolink-screenshot/raw';
import type { SecureStorageModule } from '@lynx-template/autolink-secure-storage/raw';
import type { SensorsModule } from '@lynx-template/autolink-sensors/raw';
import type { ToastModule } from '@lynx-template/autolink-toast/raw';
import type { WebSocketModule } from '@lynx-template/autolink-websocket/raw';

export type {
  AlbumUtilsModule,
  AudioPlayerModule,
  BackModule,
  BatteryModule,
  BiometricModule,
  ClipboardModule,
  DeviceInfoModule,
  DisplayModule,
  FileSystemModule,
  HapticsModule,
  KVModule,
  LocalNotificationModule,
  PermissionsModule,
  RouterModule,
  ScannerModule,
  ScreenshotModule,
  SecureStorageModule,
  SensorsModule,
  StatusBarModule,
  ToastModule,
  WebSocketModule,
};

export const NATIVE_MODULE_CONTRACT = {
  AlbumUtils: {
    name: 'AlbumUtils',
    methods: {
      pick: { name: 'pick', arity: 2 },
      saveToAlbum: { name: 'saveToAlbum', arity: 2 },
    },
  },
  AudioPlayer: {
    name: 'AudioPlayer',
    methods: {
      create: { name: 'create', arity: 2 },
      play: { name: 'play', arity: 2 },
      pause: { name: 'pause', arity: 2 },
      seek: { name: 'seek', arity: 3 },
      stop: { name: 'stop', arity: 2 },
      release: { name: 'release', arity: 2 },
      setRate: { name: 'setRate', arity: 3 },
      setVolume: { name: 'setVolume', arity: 3 },
      getProps: { name: 'getProps', arity: 2 },
    },
  },
  Back: {
    name: 'Back',
    methods: {
      setEnabled: { name: 'setEnabled', arity: 2 },
    },
  },
  Battery: {
    name: 'Battery',
    methods: {
      getInfo: { name: 'getInfo', arity: 1 },
    },
  },
  Biometric: {
    name: 'Biometric',
    methods: {
      checkSupport: { name: 'checkSupport', arity: 1 },
      authenticate: { name: 'authenticate', arity: 2 },
      createSigningKey: { name: 'createSigningKey', arity: 1 },
      signChallenge: { name: 'signChallenge', arity: 2 },
    },
  },
  Clipboard: {
    name: 'Clipboard',
    methods: {
      setString: { name: 'setString', arity: 2 },
      getString: { name: 'getString', arity: 1 },
    },
  },
  DeviceInfo: {
    name: 'DeviceInfo',
    methods: {
      getInfo: { name: 'getInfo', arity: 1 },
    },
  },
  Display: {
    name: 'Display',
    methods: {
      screenWidth: { name: 'screenWidth', arity: 1 },
      windowWidth: { name: 'windowWidth', arity: 1 },
      lynxViewWidth: { name: 'lynxViewWidth', arity: 1 },
      getBrightness: { name: 'getBrightness', arity: 1 },
      setBrightness: { name: 'setBrightness', arity: 2 },
      setKeepScreenOn: { name: 'setKeepScreenOn', arity: 2 },
    },
  },
  FileSystem: {
    name: 'FileSystem',
    methods: {
      pick: { name: 'pick', arity: 2 },
      stat: { name: 'stat', arity: 2 },
      copyToCache: { name: 'copyToCache', arity: 2 },
      readText: { name: 'readText', arity: 3 },
      readBase64: { name: 'readBase64', arity: 3 },
      writeText: { name: 'writeText', arity: 4 },
      writeBase64: { name: 'writeBase64', arity: 4 },
      delete: { name: 'delete', arity: 2 },
      listDir: { name: 'listDir', arity: 2 },
      cacheDir: { name: 'cacheDir', arity: 1 },
    },
  },
  Haptics: {
    name: 'Haptics',
    methods: {
      impact: { name: 'impact', arity: 2 },
    },
  },
  KV: {
    name: 'KV',
    methods: {
      setString: { name: 'setString', arity: 3 },
      getString: { name: 'getString', arity: 3 },
      remove: { name: 'remove', arity: 2 },
      clear: { name: 'clear', arity: 1 },
      contains: { name: 'contains', arity: 2 },
    },
  },
  LocalNotification: {
    name: 'LocalNotification',
    methods: {
      notify: { name: 'notify', arity: 2 },
      cancel: { name: 'cancel', arity: 2 },
      cancelAll: { name: 'cancelAll', arity: 1 },
    },
  },
  Permissions: {
    name: 'Permissions',
    methods: {
      check: { name: 'check', arity: 2 },
      request: { name: 'request', arity: 2 },
    },
  },
  Router: {
    name: 'Router',
    methods: {
      open: { name: 'open', arity: 2 },
      close: { name: 'close', arity: 1 },
      openURL: { name: 'openURL', arity: 2 },
    },
  },
  Scanner: {
    name: 'Scanner',
    methods: {
      scan: { name: 'scan', arity: 1 },
      scanFromImage: { name: 'scanFromImage', arity: 2 },
    },
  },
  Screenshot: {
    name: 'Screenshot',
    methods: {
      capture: { name: 'capture', arity: 2 },
      capturePage: { name: 'capturePage', arity: 2 },
    },
  },
  Sensors: {
    name: 'Sensors',
    methods: {
      isAvailable: { name: 'isAvailable', arity: 2 },
      start: { name: 'start', arity: 2 },
      stop: { name: 'stop', arity: 2 },
    },
  },
  SecureStorage: {
    name: 'SecureStorage',
    methods: {
      setString: { name: 'setString', arity: 3 },
      getString: { name: 'getString', arity: 3 },
      remove: { name: 'remove', arity: 2 },
    },
  },
  StatusBar: {
    name: 'StatusBar',
    methods: {
      setStyle: { name: 'setStyle', arity: 2 },
    },
  },
  Toast: {
    name: 'Toast',
    methods: {
      show: { name: 'show', arity: 3 },
    },
  },
  WebSocket: {
    name: 'WebSocket',
    methods: {
      connect: { name: 'connect', arity: 2 },
      sendText: { name: 'sendText', arity: 3 },
      sendBase64: { name: 'sendBase64', arity: 3 },
      close: { name: 'close', arity: 4 },
    },
  },
} as const;

export const NATIVE_MODULE_NAMES = {
  AlbumUtils: NATIVE_MODULE_CONTRACT.AlbumUtils.name,
  AudioPlayer: NATIVE_MODULE_CONTRACT.AudioPlayer.name,
  Back: NATIVE_MODULE_CONTRACT.Back.name,
  Battery: NATIVE_MODULE_CONTRACT.Battery.name,
  Biometric: NATIVE_MODULE_CONTRACT.Biometric.name,
  Clipboard: NATIVE_MODULE_CONTRACT.Clipboard.name,
  DeviceInfo: NATIVE_MODULE_CONTRACT.DeviceInfo.name,
  Display: NATIVE_MODULE_CONTRACT.Display.name,
  FileSystem: NATIVE_MODULE_CONTRACT.FileSystem.name,
  Haptics: NATIVE_MODULE_CONTRACT.Haptics.name,
  KV: NATIVE_MODULE_CONTRACT.KV.name,
  LocalNotification: NATIVE_MODULE_CONTRACT.LocalNotification.name,
  Permissions: NATIVE_MODULE_CONTRACT.Permissions.name,
  Router: NATIVE_MODULE_CONTRACT.Router.name,
  Scanner: NATIVE_MODULE_CONTRACT.Scanner.name,
  Screenshot: NATIVE_MODULE_CONTRACT.Screenshot.name,
  Sensors: NATIVE_MODULE_CONTRACT.Sensors.name,
  SecureStorage: NATIVE_MODULE_CONTRACT.SecureStorage.name,
  StatusBar: NATIVE_MODULE_CONTRACT.StatusBar.name,
  Toast: NATIVE_MODULE_CONTRACT.Toast.name,
  WebSocket: NATIVE_MODULE_CONTRACT.WebSocket.name,
} as const;

export const NATIVE_MODULE_METHODS = {
  AlbumUtils: {
    pick: NATIVE_MODULE_CONTRACT.AlbumUtils.methods.pick.name,
    saveToAlbum: NATIVE_MODULE_CONTRACT.AlbumUtils.methods.saveToAlbum.name,
  },
  AudioPlayer: {
    create: NATIVE_MODULE_CONTRACT.AudioPlayer.methods.create.name,
    play: NATIVE_MODULE_CONTRACT.AudioPlayer.methods.play.name,
    pause: NATIVE_MODULE_CONTRACT.AudioPlayer.methods.pause.name,
    seek: NATIVE_MODULE_CONTRACT.AudioPlayer.methods.seek.name,
    stop: NATIVE_MODULE_CONTRACT.AudioPlayer.methods.stop.name,
    release: NATIVE_MODULE_CONTRACT.AudioPlayer.methods.release.name,
    setRate: NATIVE_MODULE_CONTRACT.AudioPlayer.methods.setRate.name,
    setVolume: NATIVE_MODULE_CONTRACT.AudioPlayer.methods.setVolume.name,
    getProps: NATIVE_MODULE_CONTRACT.AudioPlayer.methods.getProps.name,
  },
  Back: {
    setEnabled: NATIVE_MODULE_CONTRACT.Back.methods.setEnabled.name,
  },
  Battery: {
    getInfo: NATIVE_MODULE_CONTRACT.Battery.methods.getInfo.name,
  },
  Biometric: {
    checkSupport: NATIVE_MODULE_CONTRACT.Biometric.methods.checkSupport.name,
    authenticate: NATIVE_MODULE_CONTRACT.Biometric.methods.authenticate.name,
    createSigningKey:
      NATIVE_MODULE_CONTRACT.Biometric.methods.createSigningKey.name,
    signChallenge: NATIVE_MODULE_CONTRACT.Biometric.methods.signChallenge.name,
  },
  Clipboard: {
    setString: NATIVE_MODULE_CONTRACT.Clipboard.methods.setString.name,
    getString: NATIVE_MODULE_CONTRACT.Clipboard.methods.getString.name,
  },
  DeviceInfo: {
    getInfo: NATIVE_MODULE_CONTRACT.DeviceInfo.methods.getInfo.name,
  },
  Display: {
    screenWidth: NATIVE_MODULE_CONTRACT.Display.methods.screenWidth.name,
    windowWidth: NATIVE_MODULE_CONTRACT.Display.methods.windowWidth.name,
    lynxViewWidth: NATIVE_MODULE_CONTRACT.Display.methods.lynxViewWidth.name,
    getBrightness: NATIVE_MODULE_CONTRACT.Display.methods.getBrightness.name,
    setBrightness: NATIVE_MODULE_CONTRACT.Display.methods.setBrightness.name,
    setKeepScreenOn:
      NATIVE_MODULE_CONTRACT.Display.methods.setKeepScreenOn.name,
  },
  FileSystem: {
    pick: NATIVE_MODULE_CONTRACT.FileSystem.methods.pick.name,
    stat: NATIVE_MODULE_CONTRACT.FileSystem.methods.stat.name,
    copyToCache: NATIVE_MODULE_CONTRACT.FileSystem.methods.copyToCache.name,
    readText: NATIVE_MODULE_CONTRACT.FileSystem.methods.readText.name,
    readBase64: NATIVE_MODULE_CONTRACT.FileSystem.methods.readBase64.name,
    writeText: NATIVE_MODULE_CONTRACT.FileSystem.methods.writeText.name,
    writeBase64: NATIVE_MODULE_CONTRACT.FileSystem.methods.writeBase64.name,
    delete: NATIVE_MODULE_CONTRACT.FileSystem.methods.delete.name,
    listDir: NATIVE_MODULE_CONTRACT.FileSystem.methods.listDir.name,
    cacheDir: NATIVE_MODULE_CONTRACT.FileSystem.methods.cacheDir.name,
  },
  Haptics: {
    impact: NATIVE_MODULE_CONTRACT.Haptics.methods.impact.name,
  },
  KV: {
    setString: NATIVE_MODULE_CONTRACT.KV.methods.setString.name,
    getString: NATIVE_MODULE_CONTRACT.KV.methods.getString.name,
    remove: NATIVE_MODULE_CONTRACT.KV.methods.remove.name,
    clear: NATIVE_MODULE_CONTRACT.KV.methods.clear.name,
    contains: NATIVE_MODULE_CONTRACT.KV.methods.contains.name,
  },
  LocalNotification: {
    notify: NATIVE_MODULE_CONTRACT.LocalNotification.methods.notify.name,
    cancel: NATIVE_MODULE_CONTRACT.LocalNotification.methods.cancel.name,
    cancelAll: NATIVE_MODULE_CONTRACT.LocalNotification.methods.cancelAll.name,
  },
  Permissions: {
    check: NATIVE_MODULE_CONTRACT.Permissions.methods.check.name,
    request: NATIVE_MODULE_CONTRACT.Permissions.methods.request.name,
  },
  Router: {
    open: NATIVE_MODULE_CONTRACT.Router.methods.open.name,
    close: NATIVE_MODULE_CONTRACT.Router.methods.close.name,
    openURL: NATIVE_MODULE_CONTRACT.Router.methods.openURL.name,
  },
  Scanner: {
    scan: NATIVE_MODULE_CONTRACT.Scanner.methods.scan.name,
    scanFromImage: NATIVE_MODULE_CONTRACT.Scanner.methods.scanFromImage.name,
  },
  Screenshot: {
    capture: NATIVE_MODULE_CONTRACT.Screenshot.methods.capture.name,
    capturePage: NATIVE_MODULE_CONTRACT.Screenshot.methods.capturePage.name,
  },
  Sensors: {
    isAvailable: NATIVE_MODULE_CONTRACT.Sensors.methods.isAvailable.name,
    start: NATIVE_MODULE_CONTRACT.Sensors.methods.start.name,
    stop: NATIVE_MODULE_CONTRACT.Sensors.methods.stop.name,
  },
  SecureStorage: {
    setString: NATIVE_MODULE_CONTRACT.SecureStorage.methods.setString.name,
    getString: NATIVE_MODULE_CONTRACT.SecureStorage.methods.getString.name,
    remove: NATIVE_MODULE_CONTRACT.SecureStorage.methods.remove.name,
  },
  StatusBar: {
    setStyle: NATIVE_MODULE_CONTRACT.StatusBar.methods.setStyle.name,
  },
  Toast: {
    show: NATIVE_MODULE_CONTRACT.Toast.methods.show.name,
  },
  WebSocket: {
    connect: NATIVE_MODULE_CONTRACT.WebSocket.methods.connect.name,
    sendText: NATIVE_MODULE_CONTRACT.WebSocket.methods.sendText.name,
    sendBase64: NATIVE_MODULE_CONTRACT.WebSocket.methods.sendBase64.name,
    close: NATIVE_MODULE_CONTRACT.WebSocket.methods.close.name,
  },
} as const;

export type NativeModuleName = keyof typeof NATIVE_MODULE_CONTRACT;
export type NativeMethodName<Name extends NativeModuleName> =
  keyof (typeof NATIVE_MODULE_METHODS)[Name] & string;

export interface NativeModuleRegistry {
  AlbumUtils?: AlbumUtilsModule;
  AudioPlayer?: AudioPlayerModule;
  Back?: BackModule;
  Battery?: BatteryModule;
  Biometric?: BiometricModule;
  Clipboard?: ClipboardModule;
  DeviceInfo?: DeviceInfoModule;
  Display?: DisplayModule;
  FileSystem?: FileSystemModule;
  Haptics?: HapticsModule;
  KV?: KVModule;
  LocalNotification?: LocalNotificationModule;
  Permissions?: PermissionsModule;
  Router?: RouterModule;
  Scanner?: ScannerModule;
  Screenshot?: ScreenshotModule;
  Sensors?: SensorsModule;
  SecureStorage?: SecureStorageModule;
  StatusBar?: StatusBarModule;
  Toast?: ToastModule;
  WebSocket?: WebSocketModule;
}
