// Generated from contracts/native-modules.json. Do not edit.
import '@lynx-app/native-runtime';
import type { LocalNotification as RawLocalNotificationModule } from '../types/platform-native-module.js';

export type LocalNotificationModule = RawLocalNotificationModule;

declare module '@lynx-app/native-runtime' {
  interface NativeModuleRegistry {
    LocalNotification?: RawLocalNotificationModule;
  }
}

/** Name the native hosts register this module under. */
export const LOCAL_NOTIFICATION_MODULE_NAME = 'LocalNotification' as const;
