import UIKit

@objcMembers
final class NativeKVModule: NSObject, LynxModule {
  static let name = "NativeKVModule"
  static let methodLookup = [
    "setString": "setString:value:callback:",
    "getString": "getString:defaultValue:callback:",
    "remove": "remove:callback:",
    "clear": "clear:",
    "contains": "contains:callback:",
  ]

  private lazy var storage = MMKV(mmapID: "lynx.native.kv")

  override init() {
    super.init()
  }

  @objc(initWithParam:)
  init(param: Any) {
    super.init()
  }

  func setString(
    _ key: String,
    value: String,
    callback: LynxCallbackBlock
  ) {
    guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          storage?.set(value, forKey: key) == true else {
      callback("Unable to persist MMKV key")
      return
    }
    callback("")
  }

  func getString(
    _ key: String,
    defaultValue: String?,
    callback: LynxCallbackBlock
  ) {
    let value = storage?.string(forKey: key, defaultValue: defaultValue)
    callback(value ?? NSNull())
  }

  func remove(_ key: String, callback: LynxCallbackBlock) {
    guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      callback("MMKV key must not be empty")
      return
    }
    storage?.removeValue(forKey: key)
    callback("")
  }

  func clear(_ callback: LynxCallbackBlock) {
    storage?.clearAll()
    callback("")
  }

  func contains(_ key: String, callback: LynxCallbackBlock) {
    callback(storage?.contains(key: key) == true)
  }
}
