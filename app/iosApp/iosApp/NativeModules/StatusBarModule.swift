import UIKit

enum NativeStatusBarStyle: String {
  case darkContent = "dark-content"
  case lightContent = "light-content"

  var uiStyle: UIStatusBarStyle {
    switch self {
    case .darkContent:
      return .darkContent
    case .lightContent:
      return .lightContent
    }
  }
}

@objcMembers
final class StatusBarModule: NSObject, LynxModule {
  static let name = "StatusBar"
  static let methodLookup = [
    "setStyle": "setStyle:callback:",
  ]

  private weak var host: LynxPageViewController?

  @objc(initWithParam:)
  init(param: Any) {
    host = param as? LynxPageViewController
    super.init()
  }

  override init() {
    super.init()
  }

  func setStyle(_ rawStyle: String, callback: @escaping LynxCallbackBlock) {
    guard let style = NativeStatusBarStyle(rawValue: rawStyle) else {
      callback("Invalid status bar style: \(rawStyle)")
      return
    }
    DispatchQueue.main.async { [weak self] in
      guard let host = self?.host else {
        callback("StatusBar has no UIViewController host")
        return
      }
      host.setNativeStatusBarStyle(style)
      callback("")
    }
  }
}
