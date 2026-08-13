import Foundation

struct DevelopmentSettingsSnapshot {
  let apiServer: String
  let bundleServers: String
}

/// Device-local Debug overrides shared by every iOS Lynx page.
enum DevelopmentSettings {
  static var snapshot: DevelopmentSettingsSnapshot {
    #if DEBUG
    return DevelopmentSettingsSnapshot(
      apiServer: UserDefaults.standard.string(forKey: Keys.apiServer) ?? "",
      bundleServers: UserDefaults.standard.string(
        forKey: Keys.bundleServers
      ) ?? ""
    )
    #else
    return DevelopmentSettingsSnapshot(apiServer: "", bundleServers: "")
    #endif
  }

  static var apiServer: String {
    snapshot.apiServer
  }

  static func developmentURL(for bundleID: String) -> URL? {
    #if DEBUG
    guard isValidBundleID(bundleID),
          let mappings = try? parseMappings(snapshot.bundleServers),
          let mapping = mappings.first(where: { $0.bundleID == bundleID })
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
    apiServer: String,
    bundleServers: String
  ) throws -> DevelopmentSettingsSnapshot {
    #if DEBUG
    let normalizedAPI = try normalizeAPI(apiServer)
    let mappings = try parseMappings(bundleServers)
    let normalizedMappings = mappings
      .map { "\($0.bundleID)=\($0.server)" }
      .joined(separator: "\n")
    UserDefaults.standard.set(normalizedAPI, forKey: Keys.apiServer)
    UserDefaults.standard.set(normalizedMappings, forKey: Keys.bundleServers)
    return DevelopmentSettingsSnapshot(
      apiServer: normalizedAPI,
      bundleServers: normalizedMappings
    )
    #else
    throw SettingsError.unavailable
    #endif
  }

  static func clear() {
    #if DEBUG
    UserDefaults.standard.removeObject(forKey: Keys.apiServer)
    UserDefaults.standard.removeObject(forKey: Keys.bundleServers)
    #endif
  }

  private static func normalizeAPI(_ value: String) throws -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "" }
    return try validHTTPURL(trimmed, label: "API Server").absoluteString
  }

  private static func parseMappings(_ value: String) throws -> [BundleMapping] {
    var mappings: [BundleMapping] = []
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
      mappings.append(BundleMapping(
        bundleID: bundleID,
        server: normalizedServer
      ))
    }
    return mappings
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

  private struct BundleMapping {
    let bundleID: String
    let server: String
  }

  private enum Keys {
    static let apiServer = "lynx.debug.api-server"
    static let bundleServers = "lynx.debug.bundle-servers"
  }

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
