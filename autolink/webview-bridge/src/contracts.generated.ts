// Generated from per-package NativeModule declarations. Do not edit.
// Run `pnpm native:contracts:generate` after changing a declaration.

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
  Biometric: {
    name: 'Biometric',
    methods: {
      checkSupport: { name: 'checkSupport', arity: 2 },
      authenticate: { name: 'authenticate', arity: 2 },
      createSigningKey: { name: 'createSigningKey', arity: 2 },
      getSigningKey: { name: 'getSigningKey', arity: 2 },
      deleteSigningKey: { name: 'deleteSigningKey', arity: 2 },
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
  Device: {
    name: 'Device',
    methods: {
      getInfo: { name: 'getInfo', arity: 1 },
      getSafeAreaInsets: { name: 'getSafeAreaInsets', arity: 1 },
      setStatusBarStyle: { name: 'setStatusBarStyle', arity: 2 },
      screenWidth: { name: 'screenWidth', arity: 1 },
      windowWidth: { name: 'windowWidth', arity: 1 },
      lynxViewWidth: { name: 'lynxViewWidth', arity: 1 },
      getBrightness: { name: 'getBrightness', arity: 1 },
      setBrightness: { name: 'setBrightness', arity: 2 },
      setKeepScreenOn: { name: 'setKeepScreenOn', arity: 2 },
      getBatteryInfo: { name: 'getBatteryInfo', arity: 1 },
      isAvailable: { name: 'isAvailable', arity: 2 },
      start: { name: 'start', arity: 2 },
      stop: { name: 'stop', arity: 2 },
    },
  },
  DownloadManager: {
    name: 'DownloadManager',
    methods: {
      getCapabilities: { name: 'getCapabilities', arity: 1 },
      enqueue: { name: 'enqueue', arity: 2 },
      pause: { name: 'pause', arity: 2 },
      resume: { name: 'resume', arity: 2 },
      cancel: { name: 'cancel', arity: 2 },
      remove: { name: 'remove', arity: 3 },
      getTask: { name: 'getTask', arity: 2 },
      listTasks: { name: 'listTasks', arity: 1 },
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
  ImageTooling: {
    name: 'ImageTooling',
    methods: {
      info: { name: 'info', arity: 2 },
      compress: { name: 'compress', arity: 2 },
      crop: { name: 'crop', arity: 2 },
      compose: { name: 'compose', arity: 2 },
      readExif: { name: 'readExif', arity: 2 },
      writeExif: { name: 'writeExif', arity: 2 },
      removeExif: { name: 'removeExif', arity: 2 },
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
  Navigation: {
    name: 'Navigation',
    methods: {
      open: { name: 'open', arity: 2 },
      close: { name: 'close', arity: 1 },
      openForResult: { name: 'openForResult', arity: 2 },
      closeWithResult: { name: 'closeWithResult', arity: 2 },
      openURL: { name: 'openURL', arity: 2 },
      setEnabled: { name: 'setEnabled', arity: 2 },
      configure: { name: 'configure', arity: 5 },
    },
  },
  NetworkInfo: {
    name: 'NetworkInfo',
    methods: {
      getInfo: { name: 'getInfo', arity: 1 },
      start: { name: 'start', arity: 1 },
      stop: { name: 'stop', arity: 1 },
    },
  },
  Permissions: {
    name: 'Permissions',
    methods: {
      check: { name: 'check', arity: 2 },
      request: { name: 'request', arity: 2 },
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
  Share: {
    name: 'Share',
    methods: {
      share: { name: 'share', arity: 2 },
    },
  },
  Storage: {
    name: 'Storage',
    methods: {
      setString: { name: 'setString', arity: 3 },
      getString: { name: 'getString', arity: 3 },
      getStringOrNull: { name: 'getStringOrNull', arity: 2 },
      remove: { name: 'remove', arity: 2 },
      clear: { name: 'clear', arity: 1 },
      contains: { name: 'contains', arity: 2 },
      secureSetString: { name: 'secureSetString', arity: 3 },
      secureGetString: { name: 'secureGetString', arity: 3 },
      secureGetStringOrNull: { name: 'secureGetStringOrNull', arity: 2 },
      secureRemove: { name: 'secureRemove', arity: 2 },
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
  Biometric: NATIVE_MODULE_CONTRACT.Biometric.name,
  Clipboard: NATIVE_MODULE_CONTRACT.Clipboard.name,
  Device: NATIVE_MODULE_CONTRACT.Device.name,
  DownloadManager: NATIVE_MODULE_CONTRACT.DownloadManager.name,
  FileSystem: NATIVE_MODULE_CONTRACT.FileSystem.name,
  Haptics: NATIVE_MODULE_CONTRACT.Haptics.name,
  ImageTooling: NATIVE_MODULE_CONTRACT.ImageTooling.name,
  LocalNotification: NATIVE_MODULE_CONTRACT.LocalNotification.name,
  Navigation: NATIVE_MODULE_CONTRACT.Navigation.name,
  NetworkInfo: NATIVE_MODULE_CONTRACT.NetworkInfo.name,
  Permissions: NATIVE_MODULE_CONTRACT.Permissions.name,
  Scanner: NATIVE_MODULE_CONTRACT.Scanner.name,
  Screenshot: NATIVE_MODULE_CONTRACT.Screenshot.name,
  Share: NATIVE_MODULE_CONTRACT.Share.name,
  Storage: NATIVE_MODULE_CONTRACT.Storage.name,
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
  Biometric: {
    checkSupport: NATIVE_MODULE_CONTRACT.Biometric.methods.checkSupport.name,
    authenticate: NATIVE_MODULE_CONTRACT.Biometric.methods.authenticate.name,
    createSigningKey:
      NATIVE_MODULE_CONTRACT.Biometric.methods.createSigningKey.name,
    getSigningKey: NATIVE_MODULE_CONTRACT.Biometric.methods.getSigningKey.name,
    deleteSigningKey:
      NATIVE_MODULE_CONTRACT.Biometric.methods.deleteSigningKey.name,
    signChallenge: NATIVE_MODULE_CONTRACT.Biometric.methods.signChallenge.name,
  },
  Clipboard: {
    setString: NATIVE_MODULE_CONTRACT.Clipboard.methods.setString.name,
    getString: NATIVE_MODULE_CONTRACT.Clipboard.methods.getString.name,
  },
  Device: {
    getInfo: NATIVE_MODULE_CONTRACT.Device.methods.getInfo.name,
    getSafeAreaInsets:
      NATIVE_MODULE_CONTRACT.Device.methods.getSafeAreaInsets.name,
    setStatusBarStyle:
      NATIVE_MODULE_CONTRACT.Device.methods.setStatusBarStyle.name,
    screenWidth: NATIVE_MODULE_CONTRACT.Device.methods.screenWidth.name,
    windowWidth: NATIVE_MODULE_CONTRACT.Device.methods.windowWidth.name,
    lynxViewWidth: NATIVE_MODULE_CONTRACT.Device.methods.lynxViewWidth.name,
    getBrightness: NATIVE_MODULE_CONTRACT.Device.methods.getBrightness.name,
    setBrightness: NATIVE_MODULE_CONTRACT.Device.methods.setBrightness.name,
    setKeepScreenOn: NATIVE_MODULE_CONTRACT.Device.methods.setKeepScreenOn.name,
    getBatteryInfo: NATIVE_MODULE_CONTRACT.Device.methods.getBatteryInfo.name,
    isAvailable: NATIVE_MODULE_CONTRACT.Device.methods.isAvailable.name,
    start: NATIVE_MODULE_CONTRACT.Device.methods.start.name,
    stop: NATIVE_MODULE_CONTRACT.Device.methods.stop.name,
  },
  DownloadManager: {
    getCapabilities:
      NATIVE_MODULE_CONTRACT.DownloadManager.methods.getCapabilities.name,
    enqueue: NATIVE_MODULE_CONTRACT.DownloadManager.methods.enqueue.name,
    pause: NATIVE_MODULE_CONTRACT.DownloadManager.methods.pause.name,
    resume: NATIVE_MODULE_CONTRACT.DownloadManager.methods.resume.name,
    cancel: NATIVE_MODULE_CONTRACT.DownloadManager.methods.cancel.name,
    remove: NATIVE_MODULE_CONTRACT.DownloadManager.methods.remove.name,
    getTask: NATIVE_MODULE_CONTRACT.DownloadManager.methods.getTask.name,
    listTasks: NATIVE_MODULE_CONTRACT.DownloadManager.methods.listTasks.name,
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
  ImageTooling: {
    info: NATIVE_MODULE_CONTRACT.ImageTooling.methods.info.name,
    compress: NATIVE_MODULE_CONTRACT.ImageTooling.methods.compress.name,
    crop: NATIVE_MODULE_CONTRACT.ImageTooling.methods.crop.name,
    compose: NATIVE_MODULE_CONTRACT.ImageTooling.methods.compose.name,
    readExif: NATIVE_MODULE_CONTRACT.ImageTooling.methods.readExif.name,
    writeExif: NATIVE_MODULE_CONTRACT.ImageTooling.methods.writeExif.name,
    removeExif: NATIVE_MODULE_CONTRACT.ImageTooling.methods.removeExif.name,
  },
  LocalNotification: {
    notify: NATIVE_MODULE_CONTRACT.LocalNotification.methods.notify.name,
    cancel: NATIVE_MODULE_CONTRACT.LocalNotification.methods.cancel.name,
    cancelAll: NATIVE_MODULE_CONTRACT.LocalNotification.methods.cancelAll.name,
  },
  Navigation: {
    open: NATIVE_MODULE_CONTRACT.Navigation.methods.open.name,
    close: NATIVE_MODULE_CONTRACT.Navigation.methods.close.name,
    openForResult: NATIVE_MODULE_CONTRACT.Navigation.methods.openForResult.name,
    closeWithResult:
      NATIVE_MODULE_CONTRACT.Navigation.methods.closeWithResult.name,
    openURL: NATIVE_MODULE_CONTRACT.Navigation.methods.openURL.name,
    setEnabled: NATIVE_MODULE_CONTRACT.Navigation.methods.setEnabled.name,
    configure: NATIVE_MODULE_CONTRACT.Navigation.methods.configure.name,
  },
  NetworkInfo: {
    getInfo: NATIVE_MODULE_CONTRACT.NetworkInfo.methods.getInfo.name,
    start: NATIVE_MODULE_CONTRACT.NetworkInfo.methods.start.name,
    stop: NATIVE_MODULE_CONTRACT.NetworkInfo.methods.stop.name,
  },
  Permissions: {
    check: NATIVE_MODULE_CONTRACT.Permissions.methods.check.name,
    request: NATIVE_MODULE_CONTRACT.Permissions.methods.request.name,
  },
  Scanner: {
    scan: NATIVE_MODULE_CONTRACT.Scanner.methods.scan.name,
    scanFromImage: NATIVE_MODULE_CONTRACT.Scanner.methods.scanFromImage.name,
  },
  Screenshot: {
    capture: NATIVE_MODULE_CONTRACT.Screenshot.methods.capture.name,
    capturePage: NATIVE_MODULE_CONTRACT.Screenshot.methods.capturePage.name,
  },
  Share: {
    share: NATIVE_MODULE_CONTRACT.Share.methods.share.name,
  },
  Storage: {
    setString: NATIVE_MODULE_CONTRACT.Storage.methods.setString.name,
    getString: NATIVE_MODULE_CONTRACT.Storage.methods.getString.name,
    getStringOrNull:
      NATIVE_MODULE_CONTRACT.Storage.methods.getStringOrNull.name,
    remove: NATIVE_MODULE_CONTRACT.Storage.methods.remove.name,
    clear: NATIVE_MODULE_CONTRACT.Storage.methods.clear.name,
    contains: NATIVE_MODULE_CONTRACT.Storage.methods.contains.name,
    secureSetString:
      NATIVE_MODULE_CONTRACT.Storage.methods.secureSetString.name,
    secureGetString:
      NATIVE_MODULE_CONTRACT.Storage.methods.secureGetString.name,
    secureGetStringOrNull:
      NATIVE_MODULE_CONTRACT.Storage.methods.secureGetStringOrNull.name,
    secureRemove: NATIVE_MODULE_CONTRACT.Storage.methods.secureRemove.name,
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
