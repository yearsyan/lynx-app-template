import Foundation

struct DevelopmentSettingsSnapshot {
  let bundleServers: [BundleServer]
}

struct BundleServer: Equatable {
  let bundleID: String
  let server: String
}

/// Device-local Debug overrides shared by every iOS Lynx page.
enum DevelopmentSettings {
  static var snapshot: DevelopmentSettingsSnapshot {
    #if DEBUG
    let serialized = UserDefaults.standard.string(
      forKey: Keys.bundleServers
    ) ?? ""
    return DevelopmentSettingsSnapshot(
      bundleServers: (try? parseMappings(serialized)) ?? []
    )
    #else
    return DevelopmentSettingsSnapshot(bundleServers: [])
    #endif
  }

  static func developmentURL(for bundleID: String) -> URL? {
    #if DEBUG
    guard isValidBundleID(bundleID),
          let mapping = snapshot.bundleServers.first(where: {
            $0.bundleID == bundleID
          })
    else {
      return nil
    }
    return resolveBundleURL(bundleID: bundleID, server: mapping.server)
    #else
    return nil
    #endif
  }

  @discardableResult
  static func save(
    bundleServers: [BundleServer]
  ) throws -> DevelopmentSettingsSnapshot {
    #if DEBUG
    let mappings = try normalizeMappings(bundleServers)
    let normalizedMappings = mappings
      .map { "\($0.bundleID)=\($0.server)" }
      .joined(separator: "\n")
    UserDefaults.standard.set(normalizedMappings, forKey: Keys.bundleServers)
    return DevelopmentSettingsSnapshot(bundleServers: mappings)
    #else
    throw SettingsError.unavailable
    #endif
  }

  static func validatedBundleServer(
    bundleID: String,
    server: String
  ) throws -> BundleServer {
    try normalizeMapping(
      BundleServer(bundleID: bundleID, server: server),
      label: "Bundle server"
    )
  }

  static var loadedBundleIDs: [String] {
    #if DEBUG
    return (UserDefaults.standard.stringArray(forKey: Keys.loadedBundles) ?? [])
      .filter(isValidBundleID)
      .sorted()
    #else
    return []
    #endif
  }

  static func recordLoadedBundle(_ bundleID: String) {
    #if DEBUG
    guard isValidBundleID(bundleID) else { return }
    loadedBundlesLock.lock()
    defer { loadedBundlesLock.unlock() }
    var loaded = Set(
      UserDefaults.standard.stringArray(forKey: Keys.loadedBundles) ?? []
    )
    guard loaded.insert(bundleID).inserted else { return }
    UserDefaults.standard.set(loaded.sorted(), forKey: Keys.loadedBundles)
    #endif
  }

  static func clear() {
    #if DEBUG
    UserDefaults.standard.removeObject(forKey: Keys.bundleServers)
    #endif
  }

  /// Reads the previous line-based format so existing Debug installs migrate in place.
  private static func parseMappings(_ value: String) throws -> [BundleServer] {
    var mappings: [BundleServer] = []
    var seen = Set<String>()
    for (offset, originalLine) in value.components(separatedBy: .newlines)
      .enumerated() {
      let line = originalLine.trimmingCharacters(in: .whitespaces)
      guard !line.isEmpty, !line.hasPrefix("#") else { continue }
      guard let separator = line.firstIndex(of: "="),
            separator != line.startIndex,
            separator != line.index(before: line.endIndex)
      else {
        throw SettingsError.invalid(
          "Line \(offset + 1) must use bundle-id=server-url"
        )
      }
      let bundleID = String(line[..<separator])
        .trimmingCharacters(in: .whitespaces)
      let server = String(line[line.index(after: separator)...])
        .trimmingCharacters(in: .whitespaces)
      guard isValidBundleID(bundleID) else {
        throw SettingsError.invalid(
          "Line \(offset + 1) has an invalid bundle ID: \(bundleID)"
        )
      }
      guard seen.insert(bundleID).inserted else {
        throw SettingsError.invalid(
          "Line \(offset + 1) repeats bundle ID: \(bundleID)"
        )
      }
      let normalizedServer = try validHTTPURL(
        server,
        label: "Line \(offset + 1)"
      ).absoluteString
      mappings.append(BundleServer(
        bundleID: bundleID,
        server: normalizedServer
      ))
    }
    return mappings
  }

  private static func normalizeMappings(
    _ mappings: [BundleServer]
  ) throws -> [BundleServer] {
    var seen = Set<String>()
    return try mappings.enumerated().map { offset, mapping in
      let normalized = try normalizeMapping(
        mapping,
        label: "Entry \(offset + 1)"
      )
      guard seen.insert(normalized.bundleID).inserted else {
        throw SettingsError.invalid(
          "Entry \(offset + 1) repeats bundle ID: \(normalized.bundleID)"
        )
      }
      return normalized
    }
  }

  private static func normalizeMapping(
    _ mapping: BundleServer,
    label: String
  ) throws -> BundleServer {
    let bundleID = mapping.bundleID.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    guard isValidBundleID(bundleID) else {
      throw SettingsError.invalid(
        "\(label) has an invalid bundle ID: \(bundleID)"
      )
    }
    let server = mapping.server.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    return BundleServer(
      bundleID: bundleID,
      server: try validHTTPURL(server, label: label).absoluteString
    )
  }

  private static func validHTTPURL(_ value: String, label: String) throws -> URL {
    guard let components = URLComponents(string: value),
          let scheme = components.scheme?.lowercased(),
          scheme == "http" || scheme == "https",
          components.host != nil,
          let url = components.url
    else {
      throw SettingsError.invalid(
        "\(label) must be a valid http:// or https:// URL"
      )
    }
    return url
  }

  private static func resolveBundleURL(
    bundleID: String,
    server: String
  ) -> URL? {
    guard let url = URL(string: server) else { return nil }
    if url.path.hasSuffix(".lynx.bundle") { return url }
    guard var components = URLComponents(
      url: url,
      resolvingAgainstBaseURL: false
    ) else {
      return nil
    }
    var path = components.percentEncodedPath
    if !path.hasSuffix("/") { path += "/" }
    components.percentEncodedPath = path + "\(bundleID).lynx.bundle"
    return components.url
  }

  private static func isValidBundleID(_ value: String) -> Bool {
    value.range(
      of: "^[a-z0-9][a-z0-9-]*$",
      options: .regularExpression
    ) != nil
  }

  private enum Keys {
    static let bundleServers = "lynx.debug.bundle-servers"
    static let loadedBundles = "lynx.debug.loaded-bundles"
  }

  private static let loadedBundlesLock = NSLock()

  private enum SettingsError: LocalizedError {
    case invalid(String)
    case unavailable

    var errorDescription: String? {
      switch self {
      case let .invalid(message):
        return message
      case .unavailable:
        return "Development settings are unavailable in release builds."
      }
    }
  }
}
