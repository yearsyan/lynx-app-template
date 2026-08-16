import UIKit

@objcMembers
final class NativeRouterModule: NSObject, LynxModule {
  static let name = "NativeRouterModule"
  static let methodLookup = [
    "open": "open:callback:",
    "close": "close:",
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

  func open(_ options: NSDictionary, callback: @escaping LynxCallbackBlock) {
    guard let bundle = options["bundle"] as? String,
          bundle.range(of: "^[a-z0-9][a-z0-9-]*$", options: .regularExpression) != nil else {
      callback("Invalid Lynx bundle name")
      return
    }

    let presentation = options["presentation"] as? String ?? "push"
    let transparent = (options["transparent"] as? Bool) ?? (presentation == "sheet")
    let rawStatusBarStyle = options["statusBarStyle"] as? String
      ?? NativeStatusBarStyle.darkContent.rawValue
    guard let statusBarStyle = NativeStatusBarStyle(rawValue: rawStatusBarStyle) else {
      callback("Invalid status bar style: \(rawStatusBarStyle)")
      return
    }
    let params = options["params"] as? [String: Any] ?? [:]
    let route: [String: Any] = [
      "bundle": bundle,
      "presentation": presentation,
      "transparent": transparent,
      "statusBarStyle": statusBarStyle.rawValue,
      "params": params,
    ]

    DispatchQueue.main.async { [weak self] in
      guard let host = self?.host, host.viewIfLoaded?.window != nil else {
        callback("Native router has no visible UIViewController host")
        return
      }
      let page = LynxPageViewController(
        bundleName: bundle,
        route: route,
        transparent: transparent,
        statusBarStyle: statusBarStyle
      )
      if transparent || presentation == "sheet" {
        page.modalPresentationStyle = .overFullScreen
        page.modalTransitionStyle = .crossDissolve
        host.present(page, animated: true) { callback("") }
      } else if presentation == "push", let navigation = host.navigationController {
        navigation.pushViewController(page, animated: true)
        callback("")
      } else {
        page.modalPresentationStyle = .fullScreen
        host.present(page, animated: true) { callback("") }
      }
    }
  }

  func close(_ callback: @escaping LynxCallbackBlock) {
    DispatchQueue.main.async { [weak self] in
      guard let host = self?.host else {
        callback("Native router has no UIViewController host")
        return
      }
      if host.presentingViewController != nil {
        host.dismiss(animated: true) { callback("") }
      } else if let navigation = host.navigationController,
                navigation.viewControllers.first !== host {
        navigation.popViewController(animated: true)
        callback("")
      } else {
        callback("The root route cannot be closed")
      }
    }
  }
}
