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

/// Host navigation behind the autolinked Router module: opens another Lynx
/// bundle by pushing or presenting a LynxPageViewController from the calling
/// host. The module resolves the host from its own Lynx view, so the handler
/// stays stateless.
final class AppRouteHandler: NSObject, LynxRouteHandler {
  // The ObjC selector `openFromViewController:options:success:` imports
  // into Swift as `open(from:options:success:)`.
  func open(
    from host: UIViewController,
    options: [String: Any],
    success completion: @escaping LynxCallbackBlock
  ) {
    guard let bundle = options["bundle"] as? String,
          bundle.range(of: "^[a-z0-9][a-z0-9-]*$", options: .regularExpression) != nil else {
      completion("Invalid Lynx bundle name")
      return
    }

    let presentation = options["presentation"] as? String ?? "push"
    let transparent = (options["transparent"] as? Bool) ?? (presentation == "sheet")
    let rawAnimation = options["animation"] as? String
      ?? NativeRouteAnimation.standard.rawValue
    guard let animation = NativeRouteAnimation(rawValue: rawAnimation) else {
      completion("Invalid route animation: \(rawAnimation)")
      return
    }
    let rawStatusBarStyle = options["statusBarStyle"] as? String
      ?? NativeStatusBarStyle.darkContent.rawValue
    guard let statusBarStyle = NativeStatusBarStyle(rawValue: rawStatusBarStyle) else {
      completion("Invalid status bar style: \(rawStatusBarStyle)")
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

    DispatchQueue.main.async {
      guard host.viewIfLoaded?.window != nil else {
        completion("Router has no visible UIViewController host")
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
        host.present(page, animated: animation != .none) { completion("") }
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
        completion("")
      } else {
        page.modalPresentationStyle = .fullScreen
        if animation == .fade {
          page.modalTransitionStyle = .crossDissolve
        }
        host.present(page, animated: animation != .none) { completion("") }
      }
    }
  }

  func close(
    from host: UIViewController,
    success completion: @escaping LynxCallbackBlock
  ) {
    DispatchQueue.main.async {
      guard let page = host as? LynxPageViewController else {
        completion("The root route cannot be closed")
        return
      }
      let animated = page.routeAnimation != .none
      if page.presentingViewController != nil {
        page.dismiss(animated: animated) { completion("") }
      } else if let navigation = page.navigationController,
                navigation.viewControllers.first !== page {
        if page.routeAnimation == .fade {
          withRouteFadeTransition(on: navigation.view.layer) {
            navigation.popViewController(animated: false)
          }
        } else {
          navigation.popViewController(animated: animated)
        }
        completion("")
      } else {
        completion("The root route cannot be closed")
      }
    }
  }
}
