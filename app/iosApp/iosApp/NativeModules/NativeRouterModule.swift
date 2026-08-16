import UIKit

enum NativeRouteAnimation: String {
  case standard = "default"
  case fade
  case none
}

private func withRouteFadeTransition(on layer: CALayer, action: () -> Void) {
  let transition = CATransition()
  transition.duration = 0.25
  transition.type = .fade
  layer.add(transition, forKey: "lynx.route.fade")
  action()
}

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
    let rawAnimation = options["animation"] as? String
      ?? NativeRouteAnimation.standard.rawValue
    guard let animation = NativeRouteAnimation(rawValue: rawAnimation) else {
      callback("Invalid route animation: \(rawAnimation)")
      return
    }
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
      "animation": animation.rawValue,
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
        host.present(page, animated: animation != .none) { callback("") }
      } else if presentation == "push", let navigation = host.navigationController {
        switch animation {
        case .standard:
          navigation.pushViewController(page, animated: true)
        case .fade:
          withRouteFadeTransition(on: navigation.view.layer) {
            navigation.pushViewController(page, animated: false)
          }
        case .none:
          navigation.pushViewController(page, animated: false)
        }
        callback("")
      } else {
        page.modalPresentationStyle = .fullScreen
        if animation == .fade {
          page.modalTransitionStyle = .crossDissolve
        }
        host.present(page, animated: animation != .none) { callback("") }
      }
    }
  }

  func close(_ callback: @escaping LynxCallbackBlock) {
    DispatchQueue.main.async { [weak self] in
      guard let host = self?.host else {
        callback("Native router has no UIViewController host")
        return
      }
      let animated = host.routeAnimation != .none
      if host.presentingViewController != nil {
        host.dismiss(animated: animated) { callback("") }
      } else if let navigation = host.navigationController,
                navigation.viewControllers.first !== host {
        if host.routeAnimation == .fade {
          withRouteFadeTransition(on: navigation.view.layer) {
            navigation.popViewController(animated: false)
          }
        } else {
          navigation.popViewController(animated: animated)
        }
        callback("")
      } else {
        callback("The root route cannot be closed")
      }
    }
  }
}
