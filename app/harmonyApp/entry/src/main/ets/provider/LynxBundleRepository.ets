import { common } from '@kit.AbilityKit';
import { fileIo as fs, hash } from '@kit.CoreFileKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import http from '@ohos.net.http';
import util from '@ohos.util';
import BuildProfile from 'BuildProfile';

import { BundleConfig } from '../config/BundleConfig';
import { DevelopmentSettings } from 'entry/ets/config/DevelopmentSettings';

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

class EmbeddedBundleEntry {
  name: string = '';
  preload_bundles: Array<string> | undefined = undefined;
}

class EmbeddedBundlesManifest {
  bundles: EmbeddedBundleEntry[] = [];
}

/**
 * Shared source resolver and verified OTA cache for the HarmonyOS host.
 * EntryAbility prefetches the manifest once per process; every page entry
 * (root and pushed routes) then goes through resolveEntry, which briefly
 * waits for the manifest and for a changed bundle before falling back to the
 * best verified source. The manifest state is process-wide and confined to
 * the UI event loop.
 */
export class LynxBundleRepository {
  private static readonly CACHE_SCHEME: string = 'lynx-cache';
  private static readonly CACHE_DIRECTORY: string = 'lynx-bundles';

  static readonly MANIFEST_WAIT_MS: number = 400;
  static readonly DOWNLOAD_TIMEOUT_MS: number = 3000;
  static readonly PRELOAD_DELAY_MS: number = 200;

  // Process-wide manifest and download state (single-threaded event loop).
  private static manifestEntries: Map<string, BundleEntry> | null = null;
  private static manifestInFlight: boolean = false;
  private static manifestSettled: boolean = false;
  private static manifestWaiters: Array<(has: boolean) => void> = [];
  private static downloadsInFlight: Map<string, Array<(ok: boolean) => void>> = new Map();
  private static embeddedShaMemo: Map<string, string> = new Map();
  private static preloadMapMemo: Map<string, Array<string>> | null = null;

  /**
   * Fetches the OTA manifest once per process; concurrent callers share the
   * request and later callers get the settled outcome replayed.
   */
  static refreshManifest(): void {
    if (LynxBundleRepository.manifestSettled || LynxBundleRepository.manifestInFlight) {
      return;
    }
    if (LynxBundleRepository.hasDevelopmentOverrideForMain()) {
      LynxBundleRepository.finishManifest(null);
      return;
    }
    const manifestURL: string = BundleConfig.UPDATE_MANIFEST_URL.trim();
    if (!manifestURL.startsWith('https://')) {
      LynxBundleRepository.finishManifest(null);
      return;
    }

    LynxBundleRepository.manifestInFlight = true;
    const manifestRequest: http.HttpRequest = http.createHttp();
    manifestRequest.request(manifestURL, {
      expectDataType: http.HttpDataType.STRING,
    }).then((response: http.HttpResponse): void => {
      manifestRequest.destroy();
      if (response.responseCode < 200 || response.responseCode >= 300) {
        LynxBundleRepository.finishManifest(null);
        return;
      }
      LynxBundleRepository.finishManifest(
        LynxBundleRepository.parseManifest(
          response.result as string,
          manifestURL,
        ),
      );
    }).catch((_error: Error): void => {
      manifestRequest.destroy();
      LynxBundleRepository.finishManifest(null);
    });
  }

  private static finishManifest(entries: Map<string, BundleEntry> | null): void {
    LynxBundleRepository.manifestInFlight = false;
    LynxBundleRepository.manifestSettled = true;
    if (entries !== null) {
      LynxBundleRepository.manifestEntries = entries;
    }
    const waiters: Array<(has: boolean) => void> = LynxBundleRepository.manifestWaiters;
    LynxBundleRepository.manifestWaiters = [];
    const has: boolean = entries !== null;
    for (let index: number = 0; index < waiters.length; index++) {
      waiters[index](has);
    }
  }

  private static parseManifest(
    body: string,
    manifestURL: string,
  ): Map<string, BundleEntry> | null {
    let manifest: UpdateManifest;
    try {
      manifest = JSON.parse(body) as UpdateManifest;
    } catch (_error) {
      return null;
    }
    if (manifest.schemaVersion !== 1 || manifest.engineVersion !== BundleConfig.ENGINE_VERSION) {
      return null;
    }

    const byName: Map<string, BundleEntry> = new Map<string, BundleEntry>();
    for (let index: number = 0; index < manifest.bundles.length; index++) {
      const raw: BundleEntry = manifest.bundles[index];
      if (raw.size <= 0 || !/^[a-fA-F0-9]{64}$/.test(raw.sha256)) {
        return null;
      }
      const bundleURL: string = LynxBundleRepository.resolveURL(manifestURL, raw.url);
      if (!bundleURL.startsWith('https://')) {
        return null;
      }
      const entry: BundleEntry = new BundleEntry();
      entry.name = raw.name;
      entry.version = raw.version;
      entry.url = bundleURL;
      entry.sha256 = raw.sha256.toLowerCase();
      entry.size = raw.size;
      byName.set(raw.name, entry);
    }
    return byName;
  }

  private static resolveURL(baseURL: string, relativeURL: string): string {
    if (relativeURL.startsWith('https://') || relativeURL.startsWith('http://')) {
      return relativeURL;
    }
    const separator: number = baseURL.lastIndexOf('/');
    const normalized: string = relativeURL.startsWith('./')
      ? relativeURL.substring(2)
      : relativeURL;
    return `${baseURL.substring(0, separator + 1)}${normalized}`;
  }

  /** Resolves once the manifest settles or [timeoutMs] passes, whichever first. */
  private static waitManifestWithin(timeoutMs: number): Promise<boolean> {
    return new Promise<boolean>((resolve: (has: boolean) => void) => {
      let done: boolean = false;
      const finish: (has: boolean) => void = (has: boolean): void => {
        if (!done) {
          done = true;
          resolve(has);
        }
      };
      if (LynxBundleRepository.manifestSettled) {
        finish(LynxBundleRepository.manifestEntries !== null);
        return;
      }
      LynxBundleRepository.manifestWaiters.push(finish);
      LynxBundleRepository.refreshManifest();
      setTimeout((): void => {
        finish(LynxBundleRepository.manifestEntries !== null);
      }, timeoutMs);
    });
  }

  /**
   * Resolves once the manifest has settled, however long that takes (a
   * missing URL settles immediately; the network is bounded by the HTTP
   * stack's own timeouts). Used by the background preload.
   */
  private static whenManifestReady(): Promise<boolean> {
    return new Promise<boolean>((resolve: (has: boolean) => void) => {
      if (LynxBundleRepository.manifestSettled) {
        resolve(LynxBundleRepository.manifestEntries !== null);
        return;
      }
      LynxBundleRepository.manifestWaiters.push(resolve);
      LynxBundleRepository.refreshManifest();
    });
  }

  /**
   * Schedules the OTA preload for [triggerBundle]'s dependents 200ms after
   * its first screen: every bundle whose package.json lynxBundle.downloadAt
   * listed this one downloads in parallel when the manifest marks it
   * outdated. Bundles without an update are skipped, and in-flight downloads
   * are shared with page-entry waits, never restarted.
   */
  schedulePreloadAfterFirstScreen(
    context: common.UIAbilityContext,
    triggerBundle: string,
  ): void {
    setTimeout((): void => {
      const targets: Array<string> = LynxBundleRepository.preloadTargetsFor(context, triggerBundle);
      if (targets.length === 0) {
        return;
      }
      LynxBundleRepository.whenManifestReady().then((hasManifest: boolean): void => {
        if (!hasManifest) {
          return;
        }
        for (let index: number = 0; index < targets.length; index++) {
          // Not awaited: every target downloads in parallel.
          this.preloadIfOutdated(context, targets[index]);
        }
      });
    }, LynxBundleRepository.PRELOAD_DELAY_MS);
  }

  /** Fire-and-forget download of an outdated bundle, deduped in flight. */
  private async preloadIfOutdated(
    context: common.UIAbilityContext,
    bundleName: string,
  ): Promise<void> {
    if (this.developmentURL(bundleName).length > 0) {
      return;
    }
    const entry: BundleEntry | undefined =
      LynxBundleRepository.manifestEntries?.get(bundleName);
    if (entry === undefined) {
      return;
    }
    const currentSha: string | null = await this.currentSha(context, bundleName);
    if (entry.sha256 === currentSha) {
      return;
    }
    await this.downloadWithin(context, entry, LynxBundleRepository.DOWNLOAD_TIMEOUT_MS);
  }

  /**
   * The preload_bundles list for [bundleName] from the embedded
   * lynx-bundles.json; parsed once per process and tolerant of manifests
   * generated before the field existed.
   */
  private static preloadTargetsFor(
    context: common.UIAbilityContext,
    bundleName: string,
  ): Array<string> {
    if (LynxBundleRepository.preloadMapMemo !== null) {
      return LynxBundleRepository.preloadMapMemo?.get(bundleName) ?? [];
    }
    let parsed: Map<string, Array<string>> = new Map<string, Array<string>>();
    try {
      const content: Uint8Array = context.resourceManager
        .getRawFileContentSync('lynxbundle/lynx-bundles.json');
      const manifest: EmbeddedBundlesManifest = JSON.parse(
        new util.TextDecoder('utf-8').decodeToString(content),
      ) as EmbeddedBundlesManifest;
      for (let index: number = 0; index < manifest.bundles.length; index++) {
        const entry: EmbeddedBundleEntry = manifest.bundles[index];
        parsed.set(entry.name, entry.preload_bundles ?? []);
      }
    } catch (_error) {
      parsed = new Map<string, Array<string>>();
    }
    LynxBundleRepository.preloadMapMemo = parsed;
    return parsed.get(bundleName) ?? [];
  }

  private static hasDevelopmentOverrideForMain(): boolean {
    if (DevelopmentSettings.developmentURL(BundleConfig.BUNDLE_NAME).length > 0) {
      return true;
    }
    return BuildProfile.DEBUG && BundleConfig.developmentURL().length > 0;
  }

  developmentURL(bundleName: string): string {
    const override: string = DevelopmentSettings.developmentURL(bundleName);
    if (override.length > 0) {
      return override;
    }
    return bundleName === BundleConfig.BUNDLE_NAME
      ? BundleConfig.developmentURL()
      : '';
  }

  /** The cache URL embeds the SHA-256 so template caches key per version. */
  cachedURL(bundleName: string, version: string = ''): string {
    const query: string = version.length > 0 ? `?v=${version}` : '';
    return `${LynxBundleRepository.CACHE_SCHEME}://${bundleName}${query}`;
  }

  isCachedURL(url: string): boolean {
    return url.startsWith(`${LynxBundleRepository.CACHE_SCHEME}://`);
  }

  /**
   * Unified entry resolution for every page (root and pushed routes):
   * 1. a dev override wins immediately — development flows skip OTA;
   * 2. otherwise wait up to MANIFEST_WAIT_MS for the prefetched manifest and
   *    compare its SHA-256 with the verified cache (or the embedded asset
   *    when no download exists);
   * 3. on a mismatch, wait up to DOWNLOAD_TIMEOUT_MS for the download to
   *    finish. The result is the best verified source — a timed-out or failed
   *    download keeps the previous cache or embedded bundle; the download
   *    itself continues in the background for the next entry.
   */
  async resolveEntry(
    context: common.UIAbilityContext,
    bundleName: string,
  ): Promise<string> {
    const developmentURL: string = this.developmentURL(bundleName);
    if (developmentURL.length > 0) {
      return developmentURL;
    }

    const hasManifest: boolean =
      await LynxBundleRepository.waitManifestWithin(LynxBundleRepository.MANIFEST_WAIT_MS);
    const entry: BundleEntry | undefined = hasManifest
      ? LynxBundleRepository.manifestEntries?.get(bundleName)
      : undefined;
    const fallback: string = await this.bestURL(context, bundleName);
    if (entry === undefined) {
      return fallback;
    }
    const currentSha: string | null = await this.currentSha(context, bundleName);
    if (entry.sha256 === currentSha) {
      return fallback;
    }
    const updated: boolean = await this.downloadWithin(
      context,
      entry,
      LynxBundleRepository.DOWNLOAD_TIMEOUT_MS,
    );
    return updated ? this.cachedURL(bundleName, entry.sha256) : fallback;
  }

  /** The verified per-bundle cache when present, otherwise the embedded asset. */
  private async bestURL(
    context: common.UIAbilityContext,
    bundleName: string,
  ): Promise<string> {
    const sha: string | null = await this.verifiedCachedSha(context, bundleName);
    return sha !== null ? this.cachedURL(bundleName, sha) : this.embeddedURL(bundleName);
  }

  private embeddedURL(bundleName: string): string {
    return `${BundleConfig.EMBEDDED_BUNDLE_DIRECTORY}/${bundleName}.lynx.bundle`;
  }

  /**
   * The SHA-256 of the currently best source: the verified cache digest, or
   * the embedded asset's digest when no download exists (memoized).
   */
  private async currentSha(
    context: common.UIAbilityContext,
    bundleName: string,
  ): Promise<string | null> {
    const cached: string | null = await this.verifiedCachedSha(context, bundleName);
    if (cached !== null) {
      return cached;
    }
    return this.embeddedSha(context, bundleName);
  }

  /** Cache metadata digest after re-verifying the cached bytes, or null. */
  private async verifiedCachedSha(
    context: common.UIAbilityContext,
    bundleName: string,
  ): Promise<string | null> {
    const bundlePath: string = this.cacheBundlePath(context, bundleName);
    const metadataPath: string = this.cacheMetadataPath(context, bundleName);
    if (!fs.accessSync(bundlePath) || !fs.accessSync(metadataPath)) {
      return null;
    }
    const metadata: CacheMetadata | null = this.readCacheMetadata(metadataPath);
    if (metadata === null || metadata.engineVersion !== BundleConfig.ENGINE_VERSION) {
      return null;
    }
    try {
      const digest: string = (await hash.hash(bundlePath, 'sha256')).toLowerCase();
      return digest === metadata.sha256 ? digest : null;
    } catch (_error) {
      return null;
    }
  }

  private async embeddedSha(
    context: common.UIAbilityContext,
    bundleName: string,
  ): Promise<string | null> {
    const memoized: string | undefined =
      LynxBundleRepository.embeddedShaMemo.get(bundleName);
    if (memoized !== undefined) {
      return memoized;
    }
    try {
      const content: Uint8Array = context.resourceManager
        .getRawFileContentSync(this.embeddedURL(bundleName));
      const digest: string = await LynxBundleRepository.sha256Buffer(content);
      LynxBundleRepository.embeddedShaMemo.set(bundleName, digest);
      return digest;
    } catch (_error) {
      return null;
    }
  }

  private static async sha256Buffer(data: Uint8Array): Promise<string> {
    const md: cryptoFramework.Md = cryptoFramework.createMd('SHA256');
    await md.update({ data: data });
    const digest: cryptoFramework.DataBlob = await md.digest();
    const bytes: Uint8Array = new Uint8Array(digest.data);
    let hex: string = '';
    for (let index: number = 0; index < bytes.length; index++) {
      hex += bytes[index].toString(16).padStart(2, '0');
    }
    return hex;
  }

  /**
   * Download with a timeout: resolves once when the download finishes or the
   * timeout passes; a timed-out download keeps running for the next entry.
   */
  private async downloadWithin(
    context: common.UIAbilityContext,
    entry: BundleEntry,
    timeoutMs: number,
  ): Promise<boolean> {
    return new Promise<boolean>((resolve: (ok: boolean) => void) => {
      let done: boolean = false;
      const finish: (ok: boolean) => void = (ok: boolean): void => {
        if (!done) {
          done = true;
          resolve(ok);
        }
      };
      let waiters: Array<(ok: boolean) => void> =
        LynxBundleRepository.downloadsInFlight.get(entry.name) ?? [];
      waiters.push(finish);
      LynxBundleRepository.downloadsInFlight.set(entry.name, waiters);
      setTimeout((): void => { finish(false); }, timeoutMs);
      if (waiters.length > 1) {
        return;
      }
      this.downloadBundle(context, entry).then((ok: boolean): void => {
        const callbacks: Array<(ok: boolean) => void> =
          LynxBundleRepository.downloadsInFlight.get(entry.name) ?? [];
        LynxBundleRepository.downloadsInFlight.delete(entry.name);
        for (let index: number = 0; index < callbacks.length; index++) {
          callbacks[index](ok);
        }
      });
    });
  }

  /** Downloads and verifies [entry] into the per-bundle cache, atomically. */
  private async downloadBundle(
    context: common.UIAbilityContext,
    entry: BundleEntry,
  ): Promise<boolean> {
    const bundleRequest: http.HttpRequest = http.createHttp();
    let bundleResponse: http.HttpResponse;
    try {
      bundleResponse = await bundleRequest.request(entry.url, {
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
      });
    } catch (_error) {
      return false;
    } finally {
      bundleRequest.destroy();
    }
    if (bundleResponse.responseCode < 200 || bundleResponse.responseCode >= 300) {
      return false;
    }

    const binary: ArrayBuffer = bundleResponse.result as ArrayBuffer;
    if (binary.byteLength !== entry.size) {
      return false;
    }
    const actualDigest: string = await LynxBundleRepository.sha256Buffer(new Uint8Array(binary));
    if (actualDigest !== entry.sha256) {
      return false;
    }

    try {
      const cacheDirectory: string = this.cacheDirectory(context);
      if (!fs.accessSync(cacheDirectory)) {
        fs.mkdirSync(cacheDirectory, true);
      }
      const temporaryBundle: string = `${this.cacheBundlePath(context, entry.name)}.tmp`;
      this.writeFile(temporaryBundle, binary);
      fs.moveFileSync(temporaryBundle, this.cacheBundlePath(context, entry.name), 0);
      const metadata: CacheMetadata = new CacheMetadata();
      metadata.engineVersion = BundleConfig.ENGINE_VERSION;
      metadata.sha256 = actualDigest;
      metadata.version = entry.version;
      const metadataPath: string = this.cacheMetadataPath(context, entry.name);
      const temporaryMetadata: string = `${metadataPath}.tmp`;
      this.writeTextFile(temporaryMetadata, JSON.stringify(metadata));
      fs.moveFileSync(temporaryMetadata, metadataPath, 0);
      return true;
    } catch (error) {
      console.error(`Unable to persist bundle update: ${error}`);
      return false;
    }
  }

  readCachedBundle(context: common.UIAbilityContext, bundleName: string): ArrayBuffer {
    const path: string = this.cacheBundlePath(context, bundleName);
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

  private cacheBundlePath(
    context: common.UIAbilityContext,
    bundleName: string,
  ): string {
    return `${this.cacheDirectory(context)}/${bundleName}.lynx.bundle`;
  }

  private cacheMetadataPath(
    context: common.UIAbilityContext,
    bundleName: string,
  ): string {
    return `${this.cacheDirectory(context)}/${bundleName}.metadata.json`;
  }

  private readCacheMetadata(path: string): CacheMetadata | null {
    try {
      return JSON.parse(fs.readTextSync(path)) as CacheMetadata;
    } catch (_error) {
      return null;
    }
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
