import BuildProfile from 'BuildProfile';

/**
 * Local-only values for the HarmonyOS host.
 *
 * Keep both values empty for the embedded production bundle. During local
 * development use the Mac's LAN address, not localhost on a physical device.
 */
export class BundleConfig {
  static readonly ENGINE_VERSION: string = '3.9';
  static readonly BUNDLE_NAME: string = 'main';
  static readonly EMBEDDED_BUNDLE: string = 'main.lynx.bundle';

  // Development URL: http://192.168.1.50:3000/main.lynx.bundle
  static readonly DEV_BUNDLE_URL: string = '';

  // Production OTA manifests must use HTTPS. Empty disables update checks.
  static readonly UPDATE_MANIFEST_URL: string = '';

  static developmentURL(): string {
    return BuildProfile.DEBUG ? BundleConfig.DEV_BUNDLE_URL.trim() : '';
  }
}
