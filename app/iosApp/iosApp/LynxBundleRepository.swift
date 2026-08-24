import CryptoKit
import Foundation

/// Thread-safe single-fire flag; Swift has no AtomicBool in the stdlib.
private final class Once {
  private let lock = NSLock()
  private var done = false

  func run(_ body: () -> Void) {
    lock.lock()
    let shouldRun = !done
    done = true
    lock.unlock()
    if shouldRun { body() }
  }
}

/// Process-wide OTA manifest and download state, shared by every repository
/// instance. Accessed from URLSession callbacks, so all mutations hold the lock.
private enum ManifestState {
  static let lock = NSLock()
  static var entries: [String: BundleEntry]?
  static var inFlight = false
  static var settled = false
  static var waiters: [(Bool) -> Void] = []
  static var downloadsInFlight: [String: [(Bool) -> Void]] = [:]
  static var embeddedShaMemo: [String: String] = [:]
  static var preloadMapMemo: [String: [String]]?
}

private struct UpdateManifest: Decodable {
  let schemaVersion: Int
  let engineVersion: String
  let bundles: [BundleEntry]
}

private struct BundleEntry: Decodable {
  let name: String
  let version: String
  let url: String
  let sha256: String
  let size: Int
}

private struct CacheMetadata: Codable {
  let engineVersion: String
  let version: String
  let sha256: String
}

/// Resolves a debug server, verified OTA cache, and the app resource for any
/// bundle. The app delegate prefetches the manifest once per process
/// (`prefetchManifest()`); every page entry (root and pushed routes) then goes
/// through `resolveEntry(forBundle:...)`, which briefly waits for the manifest
/// and for a changed bundle before falling back to the best verified source.
final class LynxBundleRepository: NSObject, LynxTemplateProvider {
  private let fileManager = FileManager.default
  private let decoder = JSONDecoder()
  private let encoder = JSONEncoder()

  private lazy var cacheDirectory: URL = {
    let parent = fileManager.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    )[0]
    let directory = parent.appendingPathComponent(
      "LynxBundles",
      isDirectory: true
    )
    try? fileManager.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    return directory
  }()

  // MARK: Entry resolution

  /// Dev override, then the verified per-bundle cache, then the embedded asset.
  func url(forBundle bundleName: String) -> String {
    DevelopmentSettings.recordLoadedBundle(bundleName)
    if let development = developmentURL(for: bundleName) {
      return development.absoluteString
    }
    return bestURL(for: bundleName)
  }

  /// Unified entry resolution for every page (root and pushed routes):
  /// 1. a dev override wins immediately — development flows skip OTA;
  /// 2. otherwise wait up to `Constants.manifestWait` for the prefetched
  ///    manifest and compare its SHA-256 with the verified cache (or the
  ///    embedded asset when no download exists);
  /// 3. on a mismatch, wait up to `Constants.downloadTimeout` for the
  ///    download to finish. The result is the best verified source — a
  ///    timed-out or failed download keeps the previous cache or embedded
  ///    bundle; the download itself continues for the next entry.
  ///
  /// `completion` fires exactly once on the main thread.
  func resolveEntry(
    forBundle bundleName: String,
    completion: @escaping (String) -> Void
  ) {
    DevelopmentSettings.recordLoadedBundle(bundleName)
    if let development = developmentURL(for: bundleName) {
      DispatchQueue.main.async { completion(development.absoluteString) }
      return
    }
    Self.waitManifest(upTo: Constants.manifestWait) { [weak self] in
      guard let self else { return }
      DispatchQueue.global(qos: .userInitiated).async {
        let update = Self.manifestEntry(for: bundleName)
        let fallback = self.bestURL(for: bundleName)
        guard let update,
              update.sha256.lowercased() != self.currentSHA256(for: bundleName)
        else {
          DispatchQueue.main.async { completion(fallback) }
          return
        }
        self.download(entry: update, timeout: Constants.downloadTimeout) { success in
          DispatchQueue.main.async {
            completion(
              success
                ? self.cachedURL(for: bundleName, version: update.sha256.lowercased())
                : fallback
            )
          }
        }
      }
    }
  }

  // MARK: LynxTemplateProvider

  func loadTemplate(
    withUrl url: String!,
    onComplete callback: LynxTemplateLoadBlock!
  ) {
    guard let url else {
      callback(nil, RepositoryError.invalidURL)
      return
    }

    // The version query only versions the URL for template caches; the
    // provider always resolves the plain per-bundle cache path.
    let path = url.components(separatedBy: "?").first ?? url
    let prefix = "\(Constants.cacheScheme)://"
    if path.hasPrefix(prefix) {
      let name = String(path.dropFirst(prefix.count))
      loadFile(
        cachedBundleURL(for: name.isEmpty ? Constants.bundleName : name),
        callback: callback
      )
      return
    }

    if let remoteURL = URL(string: path),
       let scheme = remoteURL.scheme?.lowercased(),
       scheme == "http" || scheme == "https" {
      #if !DEBUG
      guard scheme == "https" else {
        callback(nil, RepositoryError.insecureReleaseURL)
        return
      }
      #endif
      URLSession.shared.dataTask(with: remoteURL) { data, _, error in
        callback(data, error)
      }.resume()
      return
    }

    let resource = path.hasSuffix(".bundle")
      ? String(path.dropLast(".bundle".count))
      : path
    guard let fileURL = Bundle.main.url(
      forResource: resource,
      withExtension: "bundle",
      subdirectory: Constants.embeddedBundleDirectory
    ) else {
      callback(nil, RepositoryError.missingEmbeddedBundle)
      return
    }
    loadFile(fileURL, callback: callback)
  }

  // MARK: URLs

  /// The cache URL embeds the SHA-256 so template caches key per version.
  func cachedURL(for bundleName: String, version: String) -> String {
    "\(Constants.cacheScheme)://\(bundleName)?v=\(version)"
  }

  /// Embedded bundle URL form; the white-screen fallback target.
  func embeddedURL(forBundle bundleName: String) -> String {
    bundleName == Constants.bundleName ? "main.lynx" : "\(bundleName).lynx"
  }

  // MARK: Manifest

  /// Fetches the OTA manifest once per process; concurrent callers share the
  /// request and later callers get the settled outcome replayed.
  static func prefetchManifest() {
    refreshManifest { _ in }
  }

  private static func refreshManifest(onComplete: @escaping (Bool) -> Void) {
    var startFetch = false
    ManifestState.lock.lock()
    if ManifestState.inFlight {
      ManifestState.waiters.append(onComplete)
    } else if ManifestState.settled {
      let result = ManifestState.entries != nil
      ManifestState.lock.unlock()
      onComplete(result)
      return
    } else {
      ManifestState.waiters.append(onComplete)
      ManifestState.inFlight = true
      startFetch = true
    }
    ManifestState.lock.unlock()

    guard startFetch else { return }
    if hasDevelopmentOverrideForMain() {
      finishManifest(nil)
      return
    }
    guard let manifestURL = configuredURL(
      environment: "LYNX_UPDATE_MANIFEST_URL",
      info: "LynxUpdateManifestURL"
    ) else {
      finishManifest(nil)
      return
    }
    #if !DEBUG
    guard manifestURL.scheme?.lowercased() == "https" else {
      finishManifest(nil)
      return
    }
    #endif

    URLSession.shared.dataTask(with: manifestURL) { data, _, error in
      guard error == nil,
            let data,
            let body = String(data: data, encoding: .utf8),
            let entries = Self.parseManifest(body, relativeTo: manifestURL)
      else {
        Self.finishManifest(nil)
        return
      }
      Self.finishManifest(entries)
    }.resume()
  }

  /// Stores a parsed version list (nil = fetch failed) and wakes every waiter.
  private static func finishManifest(_ entries: [String: BundleEntry]?) {
    ManifestState.lock.lock()
    ManifestState.inFlight = false
    ManifestState.settled = true
    if entries != nil { ManifestState.entries = entries }
    let waiters = ManifestState.waiters
    ManifestState.waiters.removeAll()
    ManifestState.lock.unlock()

    let result = entries != nil
    waiters.forEach { $0(result) }
  }

  private static func parseManifest(
    _ body: String,
    relativeTo manifestURL: URL
  ) -> [String: BundleEntry]? {
    guard let data = body.data(using: .utf8),
          let manifest = try? JSONDecoder().decode(UpdateManifest.self, from: data),
          manifest.schemaVersion == 1,
          manifest.engineVersion == Constants.engineVersion
    else { return nil }

    var byName: [String: BundleEntry] = [:]
    for entry in manifest.bundles {
      guard entry.size > 0,
            entry.sha256.range(of: "^[a-fA-F0-9]{64}$", options: .regularExpression) != nil,
            let bundleURL = URL(string: entry.url, relativeTo: manifestURL)?.absoluteURL
      else { return nil }
      #if !DEBUG
      guard bundleURL.scheme?.lowercased() == "https" else { return nil }
      #endif
      byName[entry.name] = BundleEntry(
        name: entry.name,
        version: entry.version,
        url: bundleURL.absoluteString,
        sha256: entry.sha256.lowercased(),
        size: entry.size
      )
    }
    return byName
  }

  private static func manifestEntry(for bundleName: String) -> BundleEntry? {
    ManifestState.lock.lock()
    defer { ManifestState.lock.unlock() }
    return ManifestState.entries?[bundleName]
  }

  /// Runs `onDone` once, as soon as the manifest settles or `timeout` passes.
  private static func waitManifest(
    upTo timeout: TimeInterval,
    onDone: @escaping () -> Void
  ) {
    let once = Once()
    func fire() { once.run(onDone) }

    var startFetch = false
    ManifestState.lock.lock()
    if ManifestState.settled {
      ManifestState.lock.unlock()
      fire()
      return
    }
    ManifestState.waiters.append { _ in fire() }
    // refreshManifest manages the in-flight flag itself under the lock.
    startFetch = !ManifestState.inFlight
    ManifestState.lock.unlock()

    if startFetch { refreshManifest { _ in } }
    DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { fire() }
  }

  /// Runs `onDone` once the manifest has settled, however long that takes (a
  /// missing URL settles immediately; the network is bounded by URLSession's
  /// own timeouts). Used by the background preload, which must not skip
  /// bundles just because the manifest was slow.
  private static func waitManifestSettled(onDone: @escaping () -> Void) {
    var startFetch = false
    ManifestState.lock.lock()
    if ManifestState.settled {
      ManifestState.lock.unlock()
      onDone()
      return
    }
    ManifestState.waiters.append { _ in onDone() }
    startFetch = !ManifestState.inFlight
    ManifestState.lock.unlock()
    if startFetch { refreshManifest { _ in } }
  }

  // MARK: Preload

  /// Schedules the OTA preload for `triggerBundle`'s dependents 200ms after
  /// its first screen: every bundle whose package.json `lynxBundle.downloadAt`
  /// listed this one downloads in parallel when the manifest marks it
  /// outdated. Bundles without an update are skipped, and in-flight downloads
  /// are shared with page-entry waits, never restarted.
  func schedulePreloadAfterFirstScreen(for triggerBundle: String) {
    DispatchQueue.main.asyncAfter(deadline: .now() + Constants.preloadDelay) { [weak self] in
      guard let self else { return }
      let targets = Self.preloadTargets(for: triggerBundle)
      guard !targets.isEmpty else { return }
      Self.waitManifestSettled {
        DispatchQueue.global(qos: .utility).async { [weak self] in
          guard let self else { return }
          for target in targets {
            self.preloadIfOutdated(target)
          }
        }
      }
    }
  }

  /// Fire-and-forget download of an outdated bundle, deduped in flight.
  private func preloadIfOutdated(_ bundleName: String) {
    guard developmentURL(for: bundleName) == nil else { return }
    guard let update = Self.manifestEntry(for: bundleName),
          update.sha256 != currentSHA256(for: bundleName)
    else { return }
    download(entry: update, timeout: Constants.downloadTimeout) { _ in }
  }

  /// The `preload_bundles` list for `bundleName` from the embedded
  /// lynx-bundles.json; parsed once per process and tolerant of manifests
  /// generated before the field existed.
  private static func preloadTargets(for bundleName: String) -> [String] {
    ManifestState.lock.lock()
    if let memoized = ManifestState.preloadMapMemo {
      ManifestState.lock.unlock()
      return memoized[bundleName] ?? []
    }
    ManifestState.lock.unlock()

    let parsed = parseEmbeddedPreloadMap() ?? [:]
    ManifestState.lock.lock()
    ManifestState.preloadMapMemo = parsed
    ManifestState.lock.unlock()
    return parsed[bundleName] ?? []
  }

  private static func parseEmbeddedPreloadMap() -> [String: [String]]? {
    guard
      let url = Bundle.main.url(
        forResource: "lynx-bundles",
        withExtension: "json",
        subdirectory: Constants.embeddedBundleDirectory
      ),
      let data = try? Data(contentsOf: url),
      let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
      let entries = json["bundles"] as? [[String: Any]]
    else { return nil }

    var byTrigger: [String: [String]] = [:]
    for entry in entries {
      guard let name = entry["name"] as? String else { continue }
      let preload = (entry["preload_bundles"] as? [String]) ?? []
      byTrigger[name] = preload
    }
    return byTrigger
  }

  // MARK: Downloads

  /// Downloads and verifies `entry` into the per-bundle cache with a timeout:
  /// the byte count must match `size`, the SHA-256 must match, and both files
  /// are written atomically. Concurrent downloads of the same bundle share one
  /// request; a timed-out download keeps running for the next entry.
  private func download(
    entry: BundleEntry,
    timeout: TimeInterval,
    completion: @escaping (Bool) -> Void
  ) {
    let once = Once()
    func fire(_ success: Bool) { once.run { completion(success) } }

    var startDownload = false
    ManifestState.lock.lock()
    var waiters = ManifestState.downloadsInFlight[entry.name] ?? []
    waiters.append { success in fire(success) }
    ManifestState.downloadsInFlight[entry.name] = waiters
    startDownload = waiters.count == 1
    ManifestState.lock.unlock()

    DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { fire(false) }
    guard startDownload, let bundleURL = URL(string: entry.url) else {
      if !startDownload { return }
      Self.finishDownload(entry.name, false)
      return
    }

    URLSession.shared.dataTask(with: bundleURL) { data, _, error in
      guard error == nil,
            let data,
            data.count == entry.size,
            Self.sha256(data) == entry.sha256
      else {
        Self.finishDownload(entry.name, false)
        return
      }
      do {
        try data.write(to: self.cachedBundleURL(for: entry.name), options: .atomic)
        let metadata = CacheMetadata(
          engineVersion: Constants.engineVersion,
          version: entry.version,
          sha256: entry.sha256
        )
        try self.encoder.encode(metadata).write(
          to: self.cachedMetadataURL(for: entry.name),
          options: .atomic
        )
        Self.finishDownload(entry.name, true)
      } catch {
        Self.finishDownload(entry.name, false)
      }
    }.resume()
  }

  private static func finishDownload(_ bundleName: String, _ success: Bool) {
    ManifestState.lock.lock()
    let waiters = ManifestState.downloadsInFlight.removeValue(forKey: bundleName) ?? []
    ManifestState.lock.unlock()
    waiters.forEach { $0(success) }
  }

  // MARK: Source resolution

  /// The verified per-bundle cache when present, otherwise the embedded asset.
  private func bestURL(for bundleName: String) -> String {
    if let sha = cachedSHA256(for: bundleName) {
      return cachedURL(for: bundleName, version: sha)
    }
    return embeddedURL(forBundle: bundleName)
  }

  /// The SHA-256 of the currently best source: the verified cache digest, or
  /// the embedded asset's digest when no download exists (memoized).
  private func currentSHA256(for bundleName: String) -> String? {
    cachedSHA256(for: bundleName) ?? embeddedSHA256(for: bundleName)
  }

  private func cachedSHA256(for bundleName: String) -> String? {
    guard let metadataData = try? Data(contentsOf: cachedMetadataURL(for: bundleName)),
          let metadata = try? decoder.decode(CacheMetadata.self, from: metadataData),
          metadata.engineVersion == Constants.engineVersion
    else { return nil }
    guard let bundleData = try? Data(contentsOf: cachedBundleURL(for: bundleName)),
          Self.sha256(bundleData) == metadata.sha256
    else { return nil }
    return metadata.sha256
  }

  private func embeddedSHA256(for bundleName: String) -> String? {
    ManifestState.lock.lock()
    let memoized = ManifestState.embeddedShaMemo[bundleName]
    ManifestState.lock.unlock()
    if let memoized { return memoized }

    let digest = embeddedFileURL(for: bundleName).flatMap {
      try? Data(contentsOf: $0)
    }.map(Self.sha256)
    ManifestState.lock.lock()
    ManifestState.embeddedShaMemo[bundleName] = digest
    ManifestState.lock.unlock()
    return digest
  }

  // MARK: Paths and helpers

  private func cachedBundleURL(for bundleName: String) -> URL {
    cacheDirectory.appendingPathComponent("\(bundleName).lynx.bundle")
  }

  private func cachedMetadataURL(for bundleName: String) -> URL {
    cacheDirectory.appendingPathComponent("\(bundleName).metadata.json")
  }

  private func embeddedFileURL(for bundleName: String) -> URL? {
    Bundle.main.url(
      forResource: "\(bundleName).lynx",
      withExtension: "bundle",
      subdirectory: Constants.embeddedBundleDirectory
    )
  }

  private func developmentURL(for bundleName: String) -> URL? {
    if let override = DevelopmentSettings.developmentURL(for: bundleName) {
      return override
    }
    guard bundleName == Constants.bundleName else { return nil }
    return legacyDevelopmentURL
  }

  private var legacyDevelopmentURL: URL? {
    #if DEBUG
    return Self.configuredURL(environment: "LYNX_DEV_BUNDLE_URL", info: "LynxDevBundleURL")
    #else
    return nil
    #endif
  }

  private static func hasDevelopmentOverrideForMain() -> Bool {
    if DevelopmentSettings.developmentURL(for: Constants.bundleName) != nil {
      return true
    }
    #if DEBUG
    return configuredURL(environment: "LYNX_DEV_BUNDLE_URL", info: "LynxDevBundleURL") != nil
    #else
    return false
    #endif
  }

  private static func configuredURL(environment: String, info: String) -> URL? {
    let value = ProcessInfo.processInfo.environment[environment]
      ?? Bundle.main.object(forInfoDictionaryKey: info) as? String
    guard let value, !value.isEmpty else { return nil }
    return URL(string: value)
  }

  private func loadFile(
    _ url: URL,
    callback: @escaping LynxTemplateLoadBlock
  ) {
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        callback(try Data(contentsOf: url), nil)
      } catch {
        callback(nil, error)
      }
    }
  }

  private static func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private enum RepositoryError: LocalizedError {
    case invalidURL
    case insecureReleaseURL
    case missingEmbeddedBundle

    var errorDescription: String? {
      switch self {
      case .invalidURL:
        return "The Lynx bundle URL is empty."
      case .insecureReleaseURL:
        return "Release builds only load Lynx bundles over HTTPS."
      case .missingEmbeddedBundle:
        return "The embedded Lynx bundle could not be found."
      }
    }
  }

  private enum Constants {
    static let bundleName = "main"
    static let cacheScheme = "lynx-cache"
    static let embeddedBundleDirectory = "lynxbundle"
    static let engineVersion = "3.9"
    static let manifestWait: TimeInterval = 0.4
    static let downloadTimeout: TimeInterval = 3.0
    static let preloadDelay: TimeInterval = 0.2
  }
}
