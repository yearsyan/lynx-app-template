import BuildProfile from 'BuildProfile';
import url from '@ohos.url';
import { MMKV } from '@tencent/mmkv';

export class DevelopmentSettingsSnapshot {
  apiServer: string;
  bundleServers: string;

  constructor(apiServer: string = '', bundleServers: string = '') {
    this.apiServer = apiServer;
    this.bundleServers = bundleServers;
  }
}

class BundleServerMapping {
  bundleId: string;
  server: string;

  constructor(bundleId: string, server: string) {
    this.bundleId = bundleId;
    this.server = server;
  }
}

/**
 * Device-local overrides shared by every Lynx page.
 *
 * The implementation lives in main because the bundle repository is shared by
 * both build modes. Every read is nevertheless guarded by BuildProfile.DEBUG,
 * so a release build cannot observe values left behind by a debug install.
 */
export class DevelopmentSettings {
  private static readonly STORAGE_ID: string = 'lynx.debug.development-settings';
  private static readonly API_SERVER: string = 'api-server';
  private static readonly BUNDLE_SERVERS: string = 'bundle-servers';

  static snapshot(): DevelopmentSettingsSnapshot {
    if (!BuildProfile.DEBUG) {
      return new DevelopmentSettingsSnapshot('', '');
    }
    const storage: MMKV = DevelopmentSettings.storage();
    return new DevelopmentSettingsSnapshot(
      storage.decodeString(DevelopmentSettings.API_SERVER, '') ?? '',
      storage.decodeString(DevelopmentSettings.BUNDLE_SERVERS, '') ?? '',
    );
  }

  static apiServer(): string {
    return DevelopmentSettings.snapshot().apiServer;
  }

  static developmentURL(bundleId: string): string {
    if (!BuildProfile.DEBUG || !DevelopmentSettings.validBundleId(bundleId)) {
      return '';
    }
    let mappings: BundleServerMapping[];
    try {
      mappings = DevelopmentSettings.parseMappings(
        DevelopmentSettings.snapshot().bundleServers,
      );
    } catch (error) {
      console.error(`Invalid persisted Lynx development settings: ${JSON.stringify(error)}`);
      return '';
    }
    for (let index: number = 0; index < mappings.length; index++) {
      if (mappings[index].bundleId === bundleId) {
        return DevelopmentSettings.resolveBundleURL(bundleId, mappings[index].server);
      }
    }
    return '';
  }

  static save(apiServer: string, bundleServers: string): DevelopmentSettingsSnapshot {
    if (!BuildProfile.DEBUG) {
      throw new Error('Development settings are unavailable in release builds.');
    }
    const normalizedAPI: string = DevelopmentSettings.normalizeAPI(apiServer);
    const mappings: BundleServerMapping[] = DevelopmentSettings.parseMappings(bundleServers);
    const normalizedLines: string[] = [];
    for (let index: number = 0; index < mappings.length; index++) {
      normalizedLines.push(`${mappings[index].bundleId}=${mappings[index].server}`);
    }
    const normalizedMappings: string = normalizedLines.join('\n');
    const storage: MMKV = DevelopmentSettings.storage();
    if (!storage.encodeString(DevelopmentSettings.API_SERVER, normalizedAPI) ||
      !storage.encodeString(DevelopmentSettings.BUNDLE_SERVERS, normalizedMappings)) {
      throw new Error('Unable to persist development settings.');
    }
    return new DevelopmentSettingsSnapshot(normalizedAPI, normalizedMappings);
  }

  static clear(): void {
    if (!BuildProfile.DEBUG) {
      return;
    }
    DevelopmentSettings.storage().clearAll();
  }

  private static storage(): MMKV {
    return MMKV.mmkvWithID(DevelopmentSettings.STORAGE_ID);
  }

  private static normalizeAPI(value: string): string {
    const trimmed: string = value.trim();
    return trimmed.length === 0
      ? ''
      : DevelopmentSettings.requireHTTPURL(trimmed, 'API Server');
  }

  private static parseMappings(value: string): BundleServerMapping[] {
    const mappings: BundleServerMapping[] = [];
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
      mappings.push(new BundleServerMapping(
        bundleId,
        DevelopmentSettings.requireHTTPURL(server, `Line ${index + 1}`),
      ));
    }
    return mappings;
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
