/**
 * Raw privileged AppInstaller NativeModule transport contract.
 *
 * The library is disabled by default. Android validates a staged self-update
 * before handing it to the system installer; iOS and HarmonyOS report the
 * capability as unsupported.
 *
 * @lynxmodule
 */
export declare class AppInstaller {
  getCapabilities(
    callback: (result: {
      value?: { supported: boolean; permissionGranted: boolean };
      error?: string;
    }) => void,
  ): void;
  openPermissionSettings(callback: (error: string) => void): void;
  launchInstall(
    options: {
      uri: string;
      expectedPackageName: string;
      expectedVersionCode: number;
      expectedSha256: string;
    },
    callback: (result: {
      value?: { status: 'launched' };
      error?: string;
    }) => void,
  ): void;
}
