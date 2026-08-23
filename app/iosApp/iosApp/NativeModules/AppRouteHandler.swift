import UIKit

enum NativeRouteAnimation: String {
  case standard = "default"
  case fade
  case none
}

enum NativeRoutePresentation: String {
  case page
  case inputDialog
  case overlay
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
  let presentation: NativeRoutePresentation
  let statusBarStyle: NativeStatusBarStyle
  let params: [String: Any]
  let presentScrimColor: UIColor?
  let presentBackdropTransition: Bool
  let presentEnterAnimation: PresentContentAnimationOptions
  let presentExitAnimation: PresentContentAnimationOptions
  let presentBackdropBlur: Bool
  let presentIOSSwipeDown: Bool
  let presentDragDownToDismiss: Bool

  var routeData: [String: Any] {
    [
      "bundle": bundle,
      "statusBarStyle": statusBarStyle.rawValue,
      "animation": animation.rawValue,
      "presentation": presentation.rawValue,
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
/// stateless. `presentation: 'overlay'` snapshots the calling page first; the
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
      guard self.openRoute(route, from: host, resultToken: nil) else {
        completion("Router cannot open a route from the current host")
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
      guard self.openRoute(route, from: host, resultToken: token) else {
        Self.pendingResults.removeValue(forKey: token)
        onResult(Self.errorEnvelope("Router cannot open a route from the current host"))
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
    guard let page = host as? LynxPageViewController else {
      completion("The root route cannot be closed")
      return
    }
    if page.isInputDialogRoute, page.presentingViewController != nil {
      page.requestDialogDismiss {
        page.dismiss(animated: false) {
          completion("")
        }
      }
      return
    }
    guard let navigation = page.navigationController,
          navigation.viewControllers.first !== page else {
      completion("The root route cannot be closed")
      return
    }
    if page.isOverlayRoute {
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

  /// Opens the validated route in either the navigation stack or its own
  /// keyboard-isolated modal overlay.
  private func openRoute(
    _ route: ValidatedRoute,
    from host: UIViewController,
    resultToken: String?
  ) -> Bool {
    guard host.viewIfLoaded?.window != nil else {
      return false
    }
    if route.presentation == .inputDialog {
      let page = makePage(route, snapshot: nil, resultToken: resultToken)
      page.modalPresentationStyle = .overFullScreen
      page.modalTransitionStyle = .crossDissolve
      page.modalPresentationCapturesStatusBarAppearance = true
      page.isModalInPresentation = true
      host.present(page, animated: false)
      return true
    }
    guard let navigation = host.navigationController else { return false }
    // Preserve an overlay page's currently resolved screen-concentric radius
    // before the nested push changes its navigation-container geometry.
    (host as? LynxPageViewController)?.preservePresentBackdropCornerClipping()
    navigation.setNavigationBarHidden(true, animated: false)
    let snapshot = route.presentation == .overlay
      ? PresentBackdrop.capture(of: host.view, blurred: route.presentBackdropBlur)
      : nil
    let page = makePage(route, snapshot: snapshot, resultToken: resultToken)
    switch route.animation {
    case .standard:
      navigation.pushViewController(page, animated: true)
    case .fade:
      withRouteFadeTransition(on: navigation.view.layer) {
        navigation.pushViewController(page, animated: false)
      }
    case .none:
      navigation.pushViewController(page, animated: false)
    }
    return true
  }

  private func makePage(
    _ route: ValidatedRoute,
    snapshot: UIImage?,
    resultToken: String?
  ) -> LynxPageViewController {
    LynxPageViewController(
      bundleName: route.bundle,
      route: route.routeData,
      snapshot: snapshot,
      statusBarStyle: route.statusBarStyle,
      presentScrimColor: route.presentScrimColor,
      presentBackdropTransition: route.presentBackdropTransition,
      presentEnterAnimation: route.presentEnterAnimation,
      presentExitAnimation: route.presentExitAnimation,
      presentIOSSwipeDownEnabled: route.presentIOSSwipeDown,
      presentDragDownToDismissEnabled: route.presentDragDownToDismiss,
      routeResultToken: resultToken
    )
  }

  private func parseRoute(_ options: [String: Any]) -> (route: ValidatedRoute?, error: String?) {
    guard let bundle = options["bundle"] as? String,
          bundle.range(of: "^[a-z0-9][a-z0-9-]*$", options: .regularExpression) != nil else {
      return (nil, "Invalid Lynx bundle name")
    }

    let rawPresentation = options["presentation"] as? String
      ?? NativeRoutePresentation.page.rawValue
    guard let presentation = NativeRoutePresentation(rawValue: rawPresentation) else {
      return (nil, "Invalid route presentation: \(rawPresentation)")
    }
    let rawAnimation = options["animation"] as? String
      ?? (presentation == .page
        ? NativeRouteAnimation.standard.rawValue
        : NativeRouteAnimation.none.rawValue)
    // Overlay routes own their open/close choreography, so they always run
    // without a system transition regardless of the animation value.
    let animation: NativeRouteAnimation
    if presentation == .overlay {
      animation = .none
    } else if let parsed = NativeRouteAnimation(rawValue: rawAnimation) {
      animation = parsed
    } else {
      return (nil, "Invalid route animation: \(rawAnimation)")
    }
    let rawStatusBarStyle = options["statusBarStyle"] as? String
      ?? NativeStatusBarStyle.darkContent.rawValue
    guard let statusBarStyle = NativeStatusBarStyle(rawValue: rawStatusBarStyle) else {
      return (nil, "Invalid status bar style: \(rawStatusBarStyle)")
    }
    let params = options["params"] as? [String: Any] ?? [:]
    let overlay = options["overlay"] as? [String: Any]
    var presentScrimColor: UIColor? = nil
    if let rawScrimColor = overlay?["scrimColor"] as? String {
      guard let parsed = UIColor(lynxHexARGB: rawScrimColor) else {
        return (nil, "Invalid overlay scrim color: \(rawScrimColor)")
      }
      presentScrimColor = parsed
    }
    let presentBackdropTransition = overlay?["backdropTransition"] as? Bool ?? true
    let legacyContentTransition = overlay?["contentTransition"] as? Bool ?? true
    let presentEnter = overlay?["enter"] as? [String: Any]
    let presentExit = overlay?["exit"] as? [String: Any]
    let presentEnterAnimation = PresentContentAnimationOptions(
      opacity: presentEnter?["opacity"] as? Bool ?? false,
      push: presentEnter?["push"] as? Bool ?? legacyContentTransition
    )
    let presentExitAnimation = PresentContentAnimationOptions(
      opacity: presentExit?["opacity"] as? Bool ?? false,
      push: presentExit?["push"] as? Bool ?? legacyContentTransition
    )
    let presentBackdropBlur = overlay?["backdropBlur"] as? Bool ?? false
    let presentIOSSwipeDown = overlay?["iosSwipeDown"] as? Bool ?? false
    let presentDragDownToDismiss = overlay?["dragDownToDismiss"] as? Bool ?? false
    return (
      ValidatedRoute(
        bundle: bundle,
        animation: animation,
        presentation: presentation,
        statusBarStyle: statusBarStyle,
        params: params,
        presentScrimColor: presentScrimColor,
        presentBackdropTransition: presentBackdropTransition,
        presentEnterAnimation: presentEnterAnimation,
        presentExitAnimation: presentExitAnimation,
        presentBackdropBlur: presentBackdropBlur,
        presentIOSSwipeDown: presentIOSSwipeDown,
        presentDragDownToDismiss: presentDragDownToDismiss
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
