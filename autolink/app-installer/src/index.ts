import {
  completeNativeCall,
  decodeNativeEnvelope,
  requireNativeModule,
} from './bridge.generated.js';

export * from './native.generated.js';

export interface AppInstallerCapabilities {
  /** True only on Android hosts that include this opt-in library. */
  supported: boolean;
  /** Android's per-app "install unknown apps" switch. */
  permissionGranted: boolean;
}

export interface InstallRequest {
  /** Absolute path, file:// URI, or readable content:// URI for the APK. */
  uri: string;
  /** Must equal both the APK package and the currently installed app. */
  expectedPackageName: string;
  /** Must exactly match the APK and be newer than the installed version. */
  expectedVersionCode: number;
  /** Lower- or upper-case SHA-256 hex for the complete APK bytes. */
  expectedSha256: string;
}

export interface InstallLaunchResult {
  /** The system installer was opened; this does not mean installation finished. */
  status: 'launched';
}

interface NativeEnvelope {
  value?: unknown;
  error?: unknown;
}

const PACKAGE_NAME = /^[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)+$/;
const SHA_256 = /^[0-9a-f]{64}$/;

function requireAppInstallerModule() {
  'background only';
  return requireNativeModule();
}

function invoke<T>(
  action: (callback: (result: unknown) => void) => void,
  decode: (value: unknown) => T,
): Promise<T> {
  'background only';
  return new Promise((resolve, reject) => {
    try {
      action((resultValue) => {
        'background only';
        try {
          const envelope = decodeNativeEnvelope(
            resultValue,
            'AppInstaller',
          ) as NativeEnvelope;
          if (typeof envelope.error === 'string' && envelope.error.length > 0) {
            reject(new Error(envelope.error));
            return;
          }
          resolve(decode(envelope.value));
        } catch (error) {
          reject(error instanceof Error ? error : new Error(String(error)));
        }
      });
    } catch (error) {
      reject(error instanceof Error ? error : new Error(String(error)));
    }
  });
}

function decodeCapabilities(value: unknown): AppInstallerCapabilities {
  'background only';
  if (typeof value !== 'object' || value === null) {
    throw new Error('AppInstaller returned invalid capabilities');
  }
  const capabilities = value as Partial<AppInstallerCapabilities>;
  if (
    typeof capabilities.supported !== 'boolean' ||
    typeof capabilities.permissionGranted !== 'boolean'
  ) {
    throw new Error('AppInstaller returned invalid capabilities');
  }
  return capabilities as AppInstallerCapabilities;
}

function decodeLaunchResult(value: unknown): InstallLaunchResult {
  'background only';
  if (
    typeof value !== 'object' ||
    value === null ||
    (value as Partial<InstallLaunchResult>).status !== 'launched'
  ) {
    throw new Error('AppInstaller returned an invalid launch result');
  }
  return { status: 'launched' };
}

function normalizeRequest(options: InstallRequest): InstallRequest {
  'background only';
  if (typeof options !== 'object' || options === null) {
    throw new Error('AppInstaller options are required');
  }
  const uri = typeof options.uri === 'string' ? options.uri.trim() : '';
  const expectedPackageName =
    typeof options.expectedPackageName === 'string'
      ? options.expectedPackageName.trim()
      : '';
  const expectedSha256 =
    typeof options.expectedSha256 === 'string'
      ? options.expectedSha256.trim().toLowerCase()
      : '';
  if (uri.length === 0 || uri.length > 8192) {
    throw new Error('Install uri must be a non-empty string');
  }
  if (
    expectedPackageName.length > 255 ||
    !PACKAGE_NAME.test(expectedPackageName)
  ) {
    throw new Error('Invalid expectedPackageName');
  }
  if (
    !Number.isSafeInteger(options.expectedVersionCode) ||
    options.expectedVersionCode < 1
  ) {
    throw new Error('expectedVersionCode must be a positive safe integer');
  }
  if (!SHA_256.test(expectedSha256)) {
    throw new Error('expectedSha256 must be 64 hexadecimal characters');
  }
  return {
    uri,
    expectedPackageName,
    expectedVersionCode: options.expectedVersionCode,
    expectedSha256,
  };
}

/**
 * Opt-in Android self-update facade. The package is deliberately absent from
 * the template's default Autolink selection because it contributes the
 * policy-restricted REQUEST_INSTALL_PACKAGES permission.
 */
export const appInstaller = {
  getCapabilities(): Promise<AppInstallerCapabilities> {
    'background only';
    return invoke(
      (callback) => requireAppInstallerModule().getCapabilities(callback),
      decodeCapabilities,
    );
  },

  /** Opens Android's per-app installer permission page; it does not wait. */
  openPermissionSettings(): Promise<void> {
    'background only';
    return completeNativeCall((callback) =>
      requireAppInstallerModule().openPermissionSettings(callback),
    );
  },

  /**
   * Validates and stages the APK before opening the system installer.
   * Resolving means only that the installer UI was launched.
   */
  launchInstall(options: InstallRequest): Promise<InstallLaunchResult> {
    'background only';
    let request: InstallRequest;
    try {
      request = normalizeRequest(options);
    } catch (error) {
      return Promise.reject(
        error instanceof Error ? error : new Error(String(error)),
      );
    }
    return invoke(
      (callback) =>
        requireAppInstallerModule().launchInstall(request, callback),
      decodeLaunchResult,
    );
  },
};
