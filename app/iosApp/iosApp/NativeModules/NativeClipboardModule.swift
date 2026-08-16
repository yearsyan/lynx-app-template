import UIKit

@objcMembers
final class NativeClipboardModule: NSObject, LynxModule {
  static let name = "NativeClipboardModule"
  static let methodLookup = [
    "setString": "setString:callback:",
    "getString": "getString:",
  ]

  override init() {
    super.init()
  }

  @objc(initWithParam:)
  init(param: Any) {
    super.init()
  }

  func setString(_ text: String, callback: LynxCallbackBlock) {
    UIPasteboard.general.string = text
    callback("")
  }

  func getString(_ callback: LynxCallbackBlock) {
    callback(UIPasteboard.general.string ?? NSNull())
  }
}
