import '@lynx-app/native-runtime';

/** Raw per-LynxView contracts implemented directly by each app host. */
export interface BackModule {
  setEnabled(enabled: boolean, callback: (error: string) => void): void;
}

export interface StatusBarModule {
  setStyle(
    style: 'dark-content' | 'light-content',
    callback: (error: string) => void,
  ): void;
}

declare module '@lynx-app/native-runtime' {
  interface NativeModuleRegistry {
    Back?: BackModule;
    StatusBar?: StatusBarModule;
  }
}

export const BACK_MODULE_NAME = 'Back' as const;
export const STATUS_BAR_MODULE_NAME = 'StatusBar' as const;
