/** Raw per-LynxView host contracts that are not app-wide Autolink libraries. */
export interface BackModule {
  setEnabled(enabled: boolean, callback: (error: string) => void): void;
}

export interface StatusBarModule {
  setStyle(
    style: 'dark-content' | 'light-content',
    callback: (error: string) => void,
  ): void;
}
