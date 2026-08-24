import { LynxContext, LynxModule } from '@lynx/lynx';

export interface NativeInstallOptions {
  uri: string;
  expectedPackageName: string;
  expectedVersionCode: number;
  expectedSha256: string;
}

class InstallerCapabilities {
  supported: boolean = false;
  permissionGranted: boolean = false;
}

class CapabilitiesResult {
  value: InstallerCapabilities = new InstallerCapabilities();
  error: string = '';
}

class InstallResult {
  value: Object | null = null;
  error: string = 'AppInstaller is not supported on HarmonyOS';
}

/**
 * Capability-compatible HarmonyOS stub. Application updates must use the
 * platform's store or enterprise deployment channel.
 */
export class AppInstallerModule extends LynxModule {
  static readonly NAME: string = 'AppInstaller';

  constructor(context: LynxContext, param?: Object) {
    super(context, param);
  }

  getCapabilities(callback: (result: CapabilitiesResult) => void): void {
    callback(new CapabilitiesResult());
  }

  openPermissionSettings(callback: (error: string) => void): void {
    callback('AppInstaller is not supported on HarmonyOS');
  }

  launchInstall(
    _options: NativeInstallOptions,
    callback: (result: InstallResult) => void,
  ): void {
    callback(new InstallResult());
  }
}
