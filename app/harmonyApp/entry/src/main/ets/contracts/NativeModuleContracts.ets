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
    case 'Back':
      switch (methodName) {
        case 'setEnabled':
          return 2;
        default:
          return -1;
      }
    case 'Battery':
      switch (methodName) {
        case 'getInfo':
          return 1;
        default:
          return -1;
      }
    case 'Biometric':
      switch (methodName) {
        case 'checkSupport':
          return 1;
        case 'authenticate':
          return 2;
        case 'createSigningKey':
          return 1;
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
    case 'DeviceInfo':
      switch (methodName) {
        case 'getInfo':
          return 1;
        default:
          return -1;
      }
    case 'Display':
      switch (methodName) {
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
    case 'KV':
      switch (methodName) {
        case 'setString':
          return 3;
        case 'getString':
          return 3;
        case 'remove':
          return 2;
        case 'clear':
          return 1;
        case 'contains':
          return 2;
        default:
          return -1;
      }
    case 'Router':
      switch (methodName) {
        case 'open':
          return 2;
        case 'close':
          return 1;
        case 'openURL':
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
    case 'Sensors':
      switch (methodName) {
        case 'isAvailable':
          return 2;
        case 'start':
          return 2;
        case 'stop':
          return 2;
        default:
          return -1;
      }
    case 'SecureStorage':
      switch (methodName) {
        case 'setString':
          return 3;
        case 'getString':
          return 3;
        case 'remove':
          return 2;
        default:
          return -1;
      }
    case 'StatusBar':
      switch (methodName) {
        case 'setStyle':
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
