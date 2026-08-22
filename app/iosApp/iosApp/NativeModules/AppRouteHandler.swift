import UIKit

enum NativeRouteAnimation: String {
  case standard = "default"
  case fade
  case none
  case present
}

private func withRouteFadeTransition(on layer: CALayer, action: () -> Void) {
  let transition = CATransition()
  transition.duration = 0.25
  transition.type = .fade
  layer.add(transition, forKey: "lynx.route.fade")
  action()
}

private struct ValidatedRoute {
  let bundle: String
  let animation: NativeRouteAnimation
  let statusBarStyle: NativeStatusBarStyle
  let params: [String: Any]
  let presentScrimColor: UIColor?
  let presentBackdropTransition: Bool
  let presentEnterAnimation: PresentContentAnimationOptions
  let presentExitAnimation: PresentContentAnimationOptions
  let presentBackdropBlur: Bool
  let presentIOSSwipeDown: Bool

  var routeData: [String: Any] {
    [
      "bundle": bundle,
      "statusBarStyle": statusBarStyle.rawValue,
      "animation": animation.rawValue,
      "params": params,
    ]
  }
}

/// A pending openForResult callback, resolved when the opened route dies.
private final class PendingRouteResult {
  let onResult: LynxCallbackBlock
  weak var opener: UIViewController?
  var result: [String: Any]?

  init(onResult: @escaping LynxCallbackBlock, opener: UIViewController?) {
    self.onResult = onResult
    self.opener = opener
  }
}

/// Host navigation behind the autolinked Router module: opens another Lynx
/// bundle by pushing a LynxPageViewController from the calling host. The
/// module resolves the host from its own Lynx view, so the handler stays
/// stateless. `animation: 'present'` snapshots the calling page first; the
/// pushed page replays that snapshot as its backdrop (see PresentBackdrop)
/// instead of using a modal transparent presentation, so the iOS-like present
/// transition also composes with the navigation back stack.
///
/// openForResult routes carry a result token on the pushed page; the pending
/// callback registry here delivers the recorded result (or none) from the
/// page's actual stack removal, which fires on every close path — close(),
/// closeWithResult(), the interactive pop gesture and the present dismiss
/// choreography alike.
final class AppRouteHandler: NSObject, LynxRouteHandler {
  // Main-thread confined: written from DispatchQueue.main blocks only.
  private static var pendingResults: [String: PendingRouteResult] = [:]
  private static var nextToken = 0

  // The ObjC selector `openFromViewController:options:success:` imports
  // into Swift as `open(from:options:success:)`.
  func open(
    from host: UIViewController,
    options: [String: Any],
    success completion: @escaping LynxCallbackBlock
  ) {
    let parsed = parseRoute(options)
    guard let route = parsed.route else {
      completion(parsed.error ?? "Invalid route options")
      return
    }
    DispatchQueue.main.async {
      guard host.viewIfLoaded?.window != nil else {
        completion("Router has no visible UIViewController host")
        return
      }
      guard self.pushRoute(route, from: host, resultToken: nil) != nil else {
        completion("Router push requires a UINavigationController host")
        return
      }
      completion("")
    }
  }

  func openForResult(
    from host: UIViewController,
    options: [String: Any],
    onResult: @escaping LynxCallbackBlock
  ) {
    let parsed = parseRoute(options)
    guard let route = parsed.route else {
      onResult(Self.errorEnvelope(parsed.error ?? "Invalid route options"))
      return
    }
    DispatchQueue.main.async {
      Self.nextToken += 1
      let token = "route-result-\(Self.nextToken)"
      Self.pruneDeadOpeners()
      Self.pendingResults[token] = PendingRouteResult(onResult: onResult, opener: host)
      guard self.pushRoute(route, from: host, resultToken: token) != nil else {
        Self.pendingResults.removeValue(forKey: token)
        onResult(Self.errorEnvelope("Router push requires a UINavigationController host"))
        return
      }
    }
  }

  func close(
    from host: UIViewController,
    success completion: @escaping LynxCallbackBlock
  ) {
    DispatchQueue.main.async {
      self.performClose(from: host, completion: completion)
    }
  }

  func closeWithResult(
    from host: UIViewController,
    result: [String: Any],
    success completion: @escaping LynxCallbackBlock
  ) {
    DispatchQueue.main.async {
      if let page = host as? LynxPageViewController, let token = page.routeResultToken {
        Self.pendingResults[token]?.result = result
      }
      self.performClose(from: host, completion: completion)
    }
  }

  /// Delivers the pending entry once, with its recorded result or none; safe
  /// from any thread (delivery itself stays on the main thread).
  static func completeRouteResult(token: String) {
    if Thread.isMainThread {
      deliverRouteResult(token: token)
    } else {
      DispatchQueue.main.async {
        Self.deliverRouteResult(token: token)
      }
    }
  }

  // MARK: Internals

  private func performClose(
    from host: UIViewController,
    completion: @escaping LynxCallbackBlock
  ) {
    guard let page = host as? LynxPageViewController,
          let navigation = page.navigationController,
          navigation.viewControllers.first !== page else {
      completion("The root route cannot be closed")
      return
    }
    if page.routeAnimation == .present {
      // The reverse choreography pops the page itself once the backdrop has
      // restored the previous page's pixels.
      page.playDismissChoreography {
        navigation.popViewController(animated: false)
        completion("")
      }
    } else if page.routeAnimation == .fade {
      withRouteFadeTransition(on: navigation.view.layer) {
        navigation.popViewController(animated: false)
      }
      completion("")
    } else {
      navigation.popViewController(animated: page.routeAnimation != .none)
      completion("")
    }
  }

  /// Pushes the validated route; nil when the host has no navigation stack.
  private func pushRoute(
    _ route: ValidatedRoute,
    from host: UIViewController,
    resultToken: String?
  ) -> UINavigationController? {
    guard host.viewIfLoaded?.window != nil,
          let navigation = host.navigationController else {
      return nil
    }
    // Preserve a present page's currently resolved screen-concentric radius
    // before the nested push changes its navigation-container geometry.
    (host as? LynxPageViewController)?.preservePresentBackdropCornerClipping()
    navigation.setNavigationBarHidden(true, animated: false)
    let snapshot = route.animation == .present
      ? PresentBackdrop.capture(of: host.view, blurred: route.presentBackdropBlur)
      : nil
    let page = LynxPageViewController(
      bundleName: route.bundle,
      route: route.routeData,
      snapshot: snapshot,
      statusBarStyle: route.statusBarStyle,
      presentScrimColor: route.presentScrimColor,
      presentBackdropTransition: route.presentBackdropTransition,
      presentEnterAnimation: route.presentEnterAnimation,
      presentExitAnimation: route.presentExitAnimation,
      presentIOSSwipeDownEnabled: route.presentIOSSwipeDown,
      routeResultToken: resultToken
    )
    switch route.animation {
    case .standard:
      navigation.pushViewController(page, animated: true)
    case .fade:
      withRouteFadeTransition(on: navigation.view.layer) {
        navigation.pushViewController(page, animated: false)
      }
    case .none, .present:
      navigation.pushViewController(page, animated: false)
    }
    return navigation
  }

  private func parseRoute(_ options: [String: Any]) -> (route: ValidatedRoute?, error: String?) {
    guard let bundle = options["bundle"] as? String,
          bundle.range(of: "^[a-z0-9][a-z0-9-]*$", options: .regularExpression) != nil else {
      return (nil, "Invalid Lynx bundle name")
    }

    let rawAnimation = options["animation"] as? String
      ?? NativeRouteAnimation.standard.rawValue
    guard let animation = NativeRouteAnimation(rawValue: rawAnimation) else {
      return (nil, "Invalid route animation: \(rawAnimation)")
    }
    let rawStatusBarStyle = options["statusBarStyle"] as? String
      ?? NativeStatusBarStyle.darkContent.rawValue
    guard let statusBarStyle = NativeStatusBarStyle(rawValue: rawStatusBarStyle) else {
      return (nil, "Invalid status bar style: \(rawStatusBarStyle)")
    }
    let params = options["params"] as? [String: Any] ?? [:]
    let present = options["present"] as? [String: Any]
    var presentScrimColor: UIColor? = nil
    if let rawScrimColor = present?["scrimColor"] as? String {
      guard let parsed = UIColor(lynxHexARGB: rawScrimColor) else {
        return (nil, "Invalid present scrim color: \(rawScrimColor)")
      }
      presentScrimColor = parsed
    }
    let presentBackdropTransition = present?["backdropTransition"] as? Bool ?? true
    let legacyContentTransition = present?["contentTransition"] as? Bool ?? true
    let presentEnter = present?["enter"] as? [String: Any]
    let presentExit = present?["exit"] as? [String: Any]
    let presentEnterAnimation = PresentContentAnimationOptions(
      opacity: presentEnter?["opacity"] as? Bool ?? false,
      push: presentEnter?["push"] as? Bool ?? legacyContentTransition
    )
    let presentExitAnimation = PresentContentAnimationOptions(
      opacity: presentExit?["opacity"] as? Bool ?? false,
      push: presentExit?["push"] as? Bool ?? legacyContentTransition
    )
    let presentBackdropBlur = present?["backdropBlur"] as? Bool ?? false
    let presentIOSSwipeDown = present?["iosSwipeDown"] as? Bool ?? false
    return (
      ValidatedRoute(
        bundle: bundle,
        animation: animation,
        statusBarStyle: statusBarStyle,
        params: params,
        presentScrimColor: presentScrimColor,
        presentBackdropTransition: presentBackdropTransition,
        presentEnterAnimation: presentEnterAnimation,
        presentExitAnimation: presentExitAnimation,
        presentBackdropBlur: presentBackdropBlur,
        presentIOSSwipeDown: presentIOSSwipeDown
      ),
      nil
    )
  }

  private static func deliverRouteResult(token: String) {
    guard let pending = pendingResults.removeValue(forKey: token),
          pending.opener != nil else {
      return
    }
    pending.onResult(pending.result.map(valueEnvelope) ?? "{}")
  }

  /// Drops entries whose awaiting page died; their JS promise can no longer run.
  private static func pruneDeadOpeners() {
    pendingResults = pendingResults.filter { $0.value.opener != nil }
  }

  private static func errorEnvelope(_ message: String) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: ["error": message]),
          let json = String(data: data, encoding: .utf8) else {
      return "{}"
    }
    return json
  }

  private static func valueEnvelope(_ result: [String: Any]) -> String {
    guard JSONSerialization.isValidJSONObject(result),
          let data = try? JSONSerialization.data(withJSONObject: ["value": result]),
          let json = String(data: data, encoding: .utf8) else {
      return "{}"
    }
    return json
  }
}
