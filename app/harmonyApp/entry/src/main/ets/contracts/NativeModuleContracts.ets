// Generated from contracts/native-modules.json. Do not edit.
// Run `pnpm native:contracts:generate` after changing the contract.

/** Returns total native arity (including callback), or -1 if not exported. */
export function nativeModuleMethodArity(
  moduleName: string,
  methodName: string,
): number {
  switch (moduleName) {
    case 'AlbumUtils':
      switch (methodName) {
        case 'pick':
          return 2;
        case 'saveToAlbum':
          return 2;
        default:
          return -1;
      }
    case 'Audio':
      switch (methodName) {
        case 'create':
          return 2;
        case 'play':
          return 2;
        case 'pause':
          return 2;
        case 'seek':
          return 3;
        case 'stop':
          return 2;
        case 'release':
          return 2;
        case 'setRate':
          return 3;
        case 'setVolume':
          return 3;
        case 'getProps':
          return 2;
        case 'recorderCreate':
          return 2;
        case 'recorderStart':
          return 2;
        case 'recorderPause':
          return 2;
        case 'recorderResume':
          return 2;
        case 'recorderStop':
          return 2;
        case 'recorderCancel':
          return 2;
        case 'recorderGetProps':
          return 2;
        case 'recorderRelease':
          return 2;
        default:
          return -1;
      }
    case 'Biometric':
      switch (methodName) {
        case 'checkSupport':
          return 2;
        case 'authenticate':
          return 2;
        case 'createSigningKey':
          return 2;
        case 'getSigningKey':
          return 2;
        case 'deleteSigningKey':
          return 2;
        case 'signChallenge':
          return 2;
        default:
          return -1;
      }
    case 'Clipboard':
      switch (methodName) {
        case 'setString':
          return 2;
        case 'getString':
          return 1;
        default:
          return -1;
      }
    case 'Device':
      switch (methodName) {
        case 'getInfo':
          return 1;
        case 'getSafeAreaInsets':
          return 1;
        case 'setStatusBarStyle':
          return 2;
        case 'screenWidth':
          return 1;
        case 'windowWidth':
          return 1;
        case 'lynxViewWidth':
          return 1;
        case 'getBrightness':
          return 1;
        case 'setBrightness':
          return 2;
        case 'setKeepScreenOn':
          return 2;
        case 'getBatteryInfo':
          return 1;
        case 'isAvailable':
          return 2;
        case 'start':
          return 2;
        case 'stop':
          return 2;
        default:
          return -1;
      }
    case 'DownloadManager':
      switch (methodName) {
        case 'getCapabilities':
          return 1;
        case 'enqueue':
          return 2;
        case 'pause':
          return 2;
        case 'resume':
          return 2;
        case 'cancel':
          return 2;
        case 'remove':
          return 3;
        case 'getTask':
          return 2;
        case 'listTasks':
          return 1;
        default:
          return -1;
      }
    case 'FileSystem':
      switch (methodName) {
        case 'pick':
          return 2;
        case 'stat':
          return 2;
        case 'copyToCache':
          return 2;
        case 'readText':
          return 3;
        case 'readBase64':
          return 3;
        case 'writeText':
          return 4;
        case 'writeBase64':
          return 4;
        case 'delete':
          return 2;
        case 'listDir':
          return 2;
        case 'cacheDir':
          return 1;
        default:
          return -1;
      }
    case 'Haptics':
      switch (methodName) {
        case 'impact':
          return 2;
        default:
          return -1;
      }
    case 'ImageTooling':
      switch (methodName) {
        case 'info':
          return 2;
        case 'compress':
          return 2;
        case 'crop':
          return 2;
        case 'compose':
          return 2;
        case 'readExif':
          return 2;
        case 'writeExif':
          return 2;
        case 'removeExif':
          return 2;
        default:
          return -1;
      }
    case 'LocalNotification':
      switch (methodName) {
        case 'notify':
          return 2;
        case 'cancel':
          return 2;
        case 'cancelAll':
          return 1;
        default:
          return -1;
      }
    case 'Navigation':
      switch (methodName) {
        case 'open':
          return 2;
        case 'close':
          return 1;
        case 'openForResult':
          return 2;
        case 'closeWithResult':
          return 2;
        case 'openURL':
          return 2;
        case 'setEnabled':
          return 2;
        case 'configure':
          return 5;
        default:
          return -1;
      }
    case 'NetworkInfo':
      switch (methodName) {
        case 'getInfo':
          return 1;
        case 'start':
          return 1;
        case 'stop':
          return 1;
        default:
          return -1;
      }
    case 'Permissions':
      switch (methodName) {
        case 'check':
          return 2;
        case 'request':
          return 2;
        default:
          return -1;
      }
    case 'Scanner':
      switch (methodName) {
        case 'scan':
          return 1;
        case 'scanFromImage':
          return 2;
        default:
          return -1;
      }
    case 'Screenshot':
      switch (methodName) {
        case 'capture':
          return 2;
        case 'capturePage':
          return 2;
        default:
          return -1;
      }
    case 'Share':
      switch (methodName) {
        case 'share':
          return 2;
        default:
          return -1;
      }
    case 'Storage':
      switch (methodName) {
        case 'setString':
          return 4;
        case 'getString':
          return 3;
        case 'getStringOrNull':
          return 2;
        case 'remove':
          return 2;
        case 'clear':
          return 1;
        case 'contains':
          return 2;
        case 'secureSetString':
          return 3;
        case 'secureGetString':
          return 3;
        case 'secureGetStringOrNull':
          return 2;
        case 'secureRemove':
          return 2;
        default:
          return -1;
      }
    case 'Toast':
      switch (methodName) {
        case 'show':
          return 3;
        default:
          return -1;
      }
    case 'WebSocket':
      switch (methodName) {
        case 'connect':
          return 2;
        case 'sendText':
          return 3;
        case 'sendBase64':
          return 3;
        case 'close':
          return 4;
        default:
          return -1;
      }
    default:
      return -1;
  }
}
