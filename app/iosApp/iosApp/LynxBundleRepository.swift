import CryptoKit
import Foundation

/// Resolves a debug server, verified OTA cache, and the app resource in order.
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

  private lazy var cachedBundle = cacheDirectory.appendingPathComponent(
    Constants.embeddedBundle
  )
  private lazy var cachedMetadata = cacheDirectory.appendingPathComponent(
    "main.metadata.json"
  )

  func startupURL() -> String {
    DevelopmentSettings.recordLoadedBundle(Constants.bundleName)
    if let developmentURL = developmentURL(for: Constants.bundleName) {
      return developmentURL.absoluteString
    }
    return hasValidCachedBundle() ? cachedURL() : "main.lynx"
  }

  func cachedURL() -> String {
    "\(Constants.cacheScheme)://\(Constants.bundleName)"
  }

  /// Embedded bundle URL form; the white-screen fallback target.
  func embeddedURL(forBundle bundleName: String) -> String {
    bundleName == Constants.bundleName ? "main.lynx" : "\(bundleName).lynx"
  }

  /// OTA policy currently applies to main; every bundle may have a debug override.
  func url(forBundle bundleName: String) -> String {
    DevelopmentSettings.recordLoadedBundle(bundleName)
    if let developmentURL = developmentURL(for: bundleName) {
      return developmentURL.absoluteString
    }
    return bundleName == Constants.bundleName
      ? startupURL()
      : "\(bundleName).lynx"
  }

  func loadTemplate(
    withUrl url: String!,
    onComplete callback: LynxTemplateLoadBlock!
  ) {
    guard let url else {
      callback(nil, RepositoryError.invalidURL)
      return
    }

    if url.hasPrefix("\(Constants.cacheScheme)://") {
      loadFile(cachedBundle, callback: callback)
      return
    }

    if let remoteURL = URL(string: url),
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

    let resource = url.hasSuffix(".bundle")
      ? String(url.dropLast(".bundle".count))
      : url
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

  func checkForUpdate(completion: @escaping (Bool) -> Void) {
    guard developmentURL(for: Constants.bundleName) == nil,
          let manifestURL = updateManifestURL else {
      completion(false)
      return
    }
    #if !DEBUG
    guard manifestURL.scheme?.lowercased() == "https" else {
      completion(false)
      return
    }
    #endif

    URLSession.shared.dataTask(with: manifestURL) { [weak self] data, _, error in
      guard let self, error == nil, let data else {
        completion(false)
        return
      }

      do {
        let manifest = try decoder.decode(UpdateManifest.self, from: data)
        guard manifest.schemaVersion == 1,
              manifest.engineVersion == Constants.engineVersion,
              let entry = manifest.bundles.first(where: {
                $0.name == Constants.bundleName
              }),
              entry.size > 0,
              entry.sha256.range(
                of: "^[a-fA-F0-9]{64}$",
                options: .regularExpression
              ) != nil,
              entry.sha256.lowercased() != cachedSHA256(),
              let bundleURL = URL(string: entry.url, relativeTo: manifestURL)?
                .absoluteURL
        else {
          completion(false)
          return
        }

        #if !DEBUG
        guard bundleURL.scheme?.lowercased() == "https" else {
          completion(false)
          return
        }
        #endif
        download(entry: entry, from: bundleURL, completion: completion)
      } catch {
        completion(false)
      }
    }.resume()
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
    return configuredURL(environment: "LYNX_DEV_BUNDLE_URL", info: "LynxDevBundleURL")
    #else
    return nil
    #endif
  }

  private var updateManifestURL: URL? {
    configuredURL(
      environment: "LYNX_UPDATE_MANIFEST_URL",
      info: "LynxUpdateManifestURL"
    )
  }

  private func configuredURL(environment: String, info: String) -> URL? {
    let value = ProcessInfo.processInfo.environment[environment]
      ?? Bundle.main.object(forInfoDictionaryKey: info) as? String
    guard let value, !value.isEmpty else { return nil }
    return URL(string: value)
  }

  private func download(
    entry: BundleEntry,
    from url: URL,
    completion: @escaping (Bool) -> Void
  ) {
    URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
      guard let self, error == nil, let data,
            data.count == entry.size,
            sha256(data) == entry.sha256.lowercased()
      else {
        completion(false)
        return
      }

      do {
        try data.write(to: cachedBundle, options: .atomic)
        let metadata = CacheMetadata(
          engineVersion: Constants.engineVersion,
          version: entry.version,
          sha256: entry.sha256.lowercased()
        )
        try encoder.encode(metadata).write(to: cachedMetadata, options: .atomic)
        completion(true)
      } catch {
        completion(false)
      }
    }.resume()
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

  private func hasValidCachedBundle() -> Bool {
    guard let metadataData = try? Data(contentsOf: cachedMetadata),
          let bundleData = try? Data(contentsOf: cachedBundle),
          let metadata = try? decoder.decode(
            CacheMetadata.self,
            from: metadataData
          )
    else {
      return false
    }
    return metadata.engineVersion == Constants.engineVersion
      && metadata.sha256 == sha256(bundleData)
  }

  private func cachedSHA256() -> String? {
    guard hasValidCachedBundle(),
          let data = try? Data(contentsOf: cachedMetadata),
          let metadata = try? decoder.decode(CacheMetadata.self, from: data)
    else {
      return nil
    }
    return metadata.sha256
  }

  private func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
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
    static let embeddedBundle = "main.lynx.bundle"
    static let engineVersion = "3.9"
  }
}
