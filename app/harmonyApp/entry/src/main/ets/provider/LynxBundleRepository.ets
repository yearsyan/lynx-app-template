import { common } from '@kit.AbilityKit';
import { fileIo as fs, hash } from '@kit.CoreFileKit';
import http from '@ohos.net.http';

import { BundleConfig } from '../config/BundleConfig';
import { DevelopmentSettings } from '../config/DevelopmentSettings';

class BundleEntry {
  name: string = '';
  version: string = '';
  url: string = '';
  sha256: string = '';
  size: number = 0;
}

class UpdateManifest {
  schemaVersion: number = 0;
  engineVersion: string = '';
  bundles: BundleEntry[] = [];
}

class CacheMetadata {
  engineVersion: string = '';
  version: string = '';
  sha256: string = '';
}

/** Shared source resolver and verified OTA cache for the HarmonyOS host. */
export class LynxBundleRepository {
  private static readonly CACHE_SCHEME: string = 'lynx-cache';
  private static readonly CACHE_DIRECTORY: string = 'lynx-bundles';
  private static readonly CACHE_METADATA: string = 'main.metadata.json';

  developmentURL(bundleName: string): string {
    const override: string = DevelopmentSettings.developmentURL(bundleName);
    if (override.length > 0) {
      return override;
    }
    return bundleName === BundleConfig.BUNDLE_NAME
      ? BundleConfig.developmentURL()
      : '';
  }

  cachedURL(version: string = ''): string {
    const query: string = version.length > 0 ? `?v=${version}` : '';
    return `${LynxBundleRepository.CACHE_SCHEME}://${BundleConfig.BUNDLE_NAME}${query}`;
  }

  isCachedURL(url: string): boolean {
    return url.startsWith(`${LynxBundleRepository.CACHE_SCHEME}://`);
  }

  cacheBundlePath(context: common.UIAbilityContext): string {
    return `${this.cacheDirectory(context)}/${BundleConfig.EMBEDDED_BUNDLE}`;
  }

  async resolveStartupURL(context: common.UIAbilityContext): Promise<string> {
    const developmentURL: string = this.developmentURL(BundleConfig.BUNDLE_NAME);
    if (developmentURL.length > 0) {
      return developmentURL;
    }

    const bundlePath: string = this.cacheBundlePath(context);
    const metadataPath: string = this.cacheMetadataPath(context);
    if (!fs.accessSync(bundlePath) || !fs.accessSync(metadataPath)) {
      return BundleConfig.EMBEDDED_BUNDLE_PATH;
    }

    try {
      const metadata: CacheMetadata | null = this.readCacheMetadata(metadataPath);
      if (metadata === null || metadata.engineVersion !== BundleConfig.ENGINE_VERSION) {
        return BundleConfig.EMBEDDED_BUNDLE_PATH;
      }
      const digest: string = (await hash.hash(bundlePath, 'sha256')).toLowerCase();
      return digest === metadata.sha256
        ? this.cachedURL(digest)
        : BundleConfig.EMBEDDED_BUNDLE_PATH;
    } catch (error) {
      console.error(`Unable to validate Lynx bundle cache: ${error}`);
      return BundleConfig.EMBEDDED_BUNDLE_PATH;
    }
  }

  async checkForUpdate(context: common.UIAbilityContext): Promise<string | null> {
    const manifestURL: string = BundleConfig.UPDATE_MANIFEST_URL.trim();
    if (this.developmentURL(BundleConfig.BUNDLE_NAME).length > 0 ||
      !manifestURL.startsWith('https://')) {
      return null;
    }

    let manifestResponse: http.HttpResponse;
    const manifestRequest: http.HttpRequest = http.createHttp();
    try {
      manifestResponse = await manifestRequest.request(manifestURL, {
        expectDataType: http.HttpDataType.STRING,
      });
    } finally {
      manifestRequest.destroy();
    }
    if (manifestResponse.responseCode < 200 || manifestResponse.responseCode >= 300) {
      return null;
    }

    const manifest: UpdateManifest = JSON.parse(
      manifestResponse.result as string,
    ) as UpdateManifest;
    if (
      manifest.schemaVersion !== 1 ||
      manifest.engineVersion !== BundleConfig.ENGINE_VERSION
    ) {
      return null;
    }

    let entry: BundleEntry | null = null;
    for (let index: number = 0; index < manifest.bundles.length; index++) {
      if (manifest.bundles[index].name === BundleConfig.BUNDLE_NAME) {
        entry = manifest.bundles[index];
        break;
      }
    }
    if (
      entry === null ||
      entry.size <= 0 ||
      !/^[a-fA-F0-9]{64}$/.test(entry.sha256)
    ) {
      return null;
    }

    const expectedDigest: string = entry.sha256.toLowerCase();
    const metadataPath: string = this.cacheMetadataPath(context);
    const cachedMetadata: CacheMetadata | null = this.readCacheMetadata(metadataPath);
    if (cachedMetadata !== null && cachedMetadata.sha256 === expectedDigest) {
      return null;
    }

    const bundleURL: string = this.resolveURL(manifestURL, entry.url);
    if (!bundleURL.startsWith('https://')) {
      return null;
    }

    let bundleResponse: http.HttpResponse;
    const bundleRequest: http.HttpRequest = http.createHttp();
    try {
      bundleResponse = await bundleRequest.request(bundleURL, {
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
      });
    } finally {
      bundleRequest.destroy();
    }
    if (bundleResponse.responseCode < 200 || bundleResponse.responseCode >= 300) {
      return null;
    }

    const binary: ArrayBuffer = bundleResponse.result as ArrayBuffer;
    if (binary.byteLength !== entry.size) {
      return null;
    }

    const cacheDirectory: string = this.cacheDirectory(context);
    if (!fs.accessSync(cacheDirectory)) {
      fs.mkdirSync(cacheDirectory, true);
    }
    const temporaryBundle: string = `${this.cacheBundlePath(context)}.tmp`;
    this.writeFile(temporaryBundle, binary);
    const actualDigest: string = (await hash.hash(temporaryBundle, 'sha256')).toLowerCase();
    if (actualDigest !== expectedDigest) {
      fs.unlinkSync(temporaryBundle);
      return null;
    }

    fs.moveFileSync(temporaryBundle, this.cacheBundlePath(context), 0);
    const metadata: CacheMetadata = new CacheMetadata();
    metadata.engineVersion = BundleConfig.ENGINE_VERSION;
    metadata.sha256 = actualDigest;
    metadata.version = entry.version;
    const temporaryMetadata: string = `${metadataPath}.tmp`;
    this.writeTextFile(temporaryMetadata, JSON.stringify(metadata));
    fs.moveFileSync(temporaryMetadata, metadataPath, 0);
    return this.cachedURL(actualDigest);
  }

  readCachedBundle(context: common.UIAbilityContext): ArrayBuffer {
    const path: string = this.cacheBundlePath(context);
    const file: fs.File = fs.openSync(path, fs.OpenMode.READ_ONLY);
    try {
      const size: number = fs.statSync(file.fd).size;
      const data: ArrayBuffer = new ArrayBuffer(size);
      fs.readSync(file.fd, data, { offset: 0, length: size });
      return data;
    } finally {
      fs.closeSync(file);
    }
  }

  private cacheDirectory(context: common.UIAbilityContext): string {
    return `${context.filesDir}/${LynxBundleRepository.CACHE_DIRECTORY}`;
  }

  private cacheMetadataPath(context: common.UIAbilityContext): string {
    return `${this.cacheDirectory(context)}/${LynxBundleRepository.CACHE_METADATA}`;
  }

  private readCacheMetadata(path: string): CacheMetadata | null {
    try {
      return JSON.parse(fs.readTextSync(path)) as CacheMetadata;
    } catch (error) {
      return null;
    }
  }

  private resolveURL(baseURL: string, relativeURL: string): string {
    if (relativeURL.startsWith('https://') || relativeURL.startsWith('http://')) {
      return relativeURL;
    }
    const separator: number = baseURL.lastIndexOf('/');
    const normalized: string = relativeURL.startsWith('./')
      ? relativeURL.substring(2)
      : relativeURL;
    return `${baseURL.substring(0, separator + 1)}${normalized}`;
  }

  private writeFile(path: string, data: ArrayBuffer): void {
    const file: fs.File = fs.openSync(
      path,
      fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC,
    );
    try {
      fs.writeSync(file.fd, data);
      fs.fsyncSync(file.fd);
    } finally {
      fs.closeSync(file);
    }
  }

  private writeTextFile(path: string, data: string): void {
    const file: fs.File = fs.openSync(
      path,
      fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC,
    );
    try {
      fs.writeSync(file.fd, data);
      fs.fsyncSync(file.fd);
    } finally {
      fs.closeSync(file);
    }
  }
}
