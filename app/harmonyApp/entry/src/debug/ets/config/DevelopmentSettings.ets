import BuildProfile from 'BuildProfile';
import url from '@ohos.url';
import { MMKV } from '@tencent/mmkv';

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

/**
 * Device-local overrides shared by every Lynx page.
 *
 * The implementation lives in the debug source root because the bundle
 * repository is shared by both build modes. Every read is also guarded by
 * BuildProfile.DEBUG so a misconfigured target cannot observe persisted debug
 * values.
 */
export class DevelopmentSettings {
  private static readonly STORAGE_ID: string = 'lynx.debug.development-settings';
  private static readonly BUNDLE_SERVERS: string = 'bundle-servers';
  private static readonly LOADED_BUNDLES: string = 'loaded-bundles';

  static snapshot(): DevelopmentSettingsSnapshot {
    if (!BuildProfile.DEBUG) {
      return new DevelopmentSettingsSnapshot();
    }
    const serialized: string = DevelopmentSettings.storage()
      .decodeString(DevelopmentSettings.BUNDLE_SERVERS, '') ?? '';
    try {
      return new DevelopmentSettingsSnapshot(
        DevelopmentSettings.parseMappings(serialized),
      );
    } catch (error) {
      console.error(`Invalid persisted Lynx development settings: ${JSON.stringify(error)}`);
      return new DevelopmentSettingsSnapshot();
    }
  }

  static developmentURL(bundleId: string): string {
    if (!BuildProfile.DEBUG || !DevelopmentSettings.validBundleId(bundleId)) {
      return '';
    }
    const mappings: BundleServer[] = DevelopmentSettings.snapshot().bundleServers;
    for (let index: number = 0; index < mappings.length; index++) {
      if (mappings[index].bundleId === bundleId) {
        return DevelopmentSettings.resolveBundleURL(bundleId, mappings[index].server);
      }
    }
    return '';
  }

  static save(bundleServers: BundleServer[]): DevelopmentSettingsSnapshot {
    if (!BuildProfile.DEBUG) {
      throw new Error('Development settings are unavailable in release builds.');
    }
    const normalized: BundleServer[] = DevelopmentSettings.normalizeMappings(bundleServers);
    const normalizedLines: string[] = [];
    for (let index: number = 0; index < normalized.length; index++) {
      normalizedLines.push(`${normalized[index].bundleId}=${normalized[index].server}`);
    }
    if (!DevelopmentSettings.storage().encodeString(
      DevelopmentSettings.BUNDLE_SERVERS,
      normalizedLines.join('\n'),
    )) {
      throw new Error('Unable to persist development settings.');
    }
    return new DevelopmentSettingsSnapshot(normalized);
  }

  static validatedBundleServer(bundleId: string, server: string): BundleServer {
    return DevelopmentSettings.normalizeMapping(
      new BundleServer(bundleId, server),
      'Bundle server',
    );
  }

  static loadedBundleIds(): string[] {
    if (!BuildProfile.DEBUG) {
      return [];
    }
    const serialized: string = DevelopmentSettings.storage()
      .decodeString(DevelopmentSettings.LOADED_BUNDLES, '[]') ?? '[]';
    try {
      const stored: string[] = JSON.parse(serialized) as string[];
      const loaded: string[] = [];
      for (let index: number = 0; index < stored.length; index++) {
        if (DevelopmentSettings.validBundleId(stored[index]) &&
          !loaded.includes(stored[index])) {
          loaded.push(stored[index]);
        }
      }
      return loaded.sort();
    } catch (error) {
      return [];
    }
  }

  static recordLoadedBundle(bundleId: string): void {
    if (!BuildProfile.DEBUG || !DevelopmentSettings.validBundleId(bundleId)) {
      return;
    }
    const loaded: string[] = DevelopmentSettings.loadedBundleIds();
    if (loaded.includes(bundleId)) {
      return;
    }
    loaded.push(bundleId);
    loaded.sort();
    if (!DevelopmentSettings.storage().encodeString(
      DevelopmentSettings.LOADED_BUNDLES,
      JSON.stringify(loaded),
    )) {
      console.error(`Unable to record loaded Lynx bundle: ${bundleId}`);
    }
  }

  static clear(): void {
    if (!BuildProfile.DEBUG) {
      return;
    }
    DevelopmentSettings.storage().removeValueForKey(DevelopmentSettings.BUNDLE_SERVERS);
  }

  private static storage(): MMKV {
    return MMKV.mmkvWithID(DevelopmentSettings.STORAGE_ID);
  }

  /** Reads the previous line-based format so existing Debug installs migrate in place. */
  private static parseMappings(value: string): BundleServer[] {
    const mappings: BundleServer[] = [];
    const seen: Set<string> = new Set<string>();
    const lines: string[] = value.split('\n');
    for (let index: number = 0; index < lines.length; index++) {
      const line: string = lines[index].trim();
      if (line.length === 0 || line.startsWith('#')) {
        continue;
      }
      const separator: number = line.indexOf('=');
      if (separator <= 0 || separator >= line.length - 1) {
        throw new Error(`Line ${index + 1} must use bundle-id=server-url`);
      }
      const bundleId: string = line.substring(0, separator).trim();
      const server: string = line.substring(separator + 1).trim();
      if (!DevelopmentSettings.validBundleId(bundleId)) {
        throw new Error(`Line ${index + 1} has an invalid bundle ID: ${bundleId}`);
      }
      if (seen.has(bundleId)) {
        throw new Error(`Line ${index + 1} repeats bundle ID: ${bundleId}`);
      }
      seen.add(bundleId);
      mappings.push(new BundleServer(
        bundleId,
        DevelopmentSettings.requireHTTPURL(server, `Line ${index + 1}`),
      ));
    }
    return mappings;
  }

  private static normalizeMappings(mappings: BundleServer[]): BundleServer[] {
    const normalized: BundleServer[] = [];
    const seen: Set<string> = new Set<string>();
    for (let index: number = 0; index < mappings.length; index++) {
      const mapping: BundleServer = DevelopmentSettings.normalizeMapping(
        mappings[index],
        `Entry ${index + 1}`,
      );
      if (seen.has(mapping.bundleId)) {
        throw new Error(`Entry ${index + 1} repeats bundle ID: ${mapping.bundleId}`);
      }
      seen.add(mapping.bundleId);
      normalized.push(mapping);
    }
    return normalized;
  }

  private static normalizeMapping(mapping: BundleServer, label: string): BundleServer {
    const bundleId: string = mapping.bundleId.trim();
    if (!DevelopmentSettings.validBundleId(bundleId)) {
      throw new Error(`${label} has an invalid bundle ID: ${bundleId}`);
    }
    return new BundleServer(
      bundleId,
      DevelopmentSettings.requireHTTPURL(mapping.server.trim(), label),
    );
  }

  private static requireHTTPURL(value: string, label: string): string {
    try {
      const parsed: url.URL = url.URL.parseURL(value);
      if ((parsed.protocol !== 'http:' && parsed.protocol !== 'https:') ||
        parsed.host.length === 0) {
        throw new Error('Unsupported URL');
      }
      return parsed.toString();
    } catch (error) {
      throw new Error(`${label} must be a valid http:// or https:// URL`);
    }
  }

  private static resolveBundleURL(bundleId: string, server: string): string {
    const parsed: url.URL = url.URL.parseURL(server);
    if (parsed.pathname.endsWith('.lynx.bundle')) {
      return parsed.toString();
    }
    let path: string = parsed.pathname;
    if (!path.endsWith('/')) {
      path += '/';
    }
    parsed.pathname = `${path}${bundleId}.lynx.bundle`;
    return parsed.toString();
  }

  private static validBundleId(value: string): boolean {
    return /^[a-z0-9][a-z0-9-]*$/.test(value);
  }
}
