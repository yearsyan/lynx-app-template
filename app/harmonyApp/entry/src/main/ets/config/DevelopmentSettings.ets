/**
 * Default no-op development settings. The debug target's extended source root
 * (src/debug) overrides this file at the same relative path with the real
 * implementation, so release builds ship no config text, MMKV keys or URL
 * parsing; every read here returns empty.
 */
export class BundleServer {
  bundleId: string;
  server: string;

  constructor(bundleId: string, server: string) {
    this.bundleId = bundleId;
    this.server = server;
  }
}

export class DevelopmentSettingsSnapshot {
  bundleServers: BundleServer[];

  constructor(bundleServers: BundleServer[] = []) {
    this.bundleServers = bundleServers;
  }
}

export class DevelopmentSettings {
  static snapshot(): DevelopmentSettingsSnapshot {
    return new DevelopmentSettingsSnapshot();
  }

  static developmentURL(bundleId: string): string {
    return '';
  }

  static save(bundleServers: BundleServer[]): DevelopmentSettingsSnapshot {
    throw new Error('Development settings are unavailable in release builds.');
  }

  static validatedBundleServer(bundleId: string, server: string): BundleServer {
    return new BundleServer(bundleId, server);
  }

  static loadedBundleIds(): string[] {
    return [];
  }

  static recordLoadedBundle(bundleId: string): void {
  }

  static clear(): void {
  }
}
