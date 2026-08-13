import UIKit

/// UIViewController-owned state machine used by NativeBackModule.
///
/// JS updates `enabled` before a gesture begins, so UIKit never waits for an
/// asynchronous Lynx callback when deciding whether the page owns Back.
@objcMembers
final class NativeBackController: NSObject, UIGestureRecognizerDelegate {
  static let eventName = "nativeBack"

  private weak var host: LynxPageViewController?
  private weak var lynxView: LynxView?
  private weak var capturedNativePopGesture: UIGestureRecognizer?
  private var nativePopWasEnabled: Bool?
  private var savedLeftBarButtonItems: [UIBarButtonItem]?
  private var savedHidesBackButton: Bool?
  private var installedBackButton = false
  private var enabled = false
  private var visible = false
  private var gestureStarted = false
  private var lastProgress: CGFloat = 0
  private var lastTouch = CGPoint.zero

  private lazy var edgeGesture: UIScreenEdgePanGestureRecognizer = {
    let gesture = UIScreenEdgePanGestureRecognizer(
      target: self,
      action: #selector(handleEdgeGesture(_:))
    )
    gesture.cancelsTouchesInView = true
    gesture.delegate = self
    gesture.isEnabled = false
    return gesture
  }()

  init(host: LynxPageViewController) {
    self.host = host
    super.init()
  }

  func attach(lynxView: LynxView) {
    self.lynxView = lynxView
    guard let host else { return }
    updateGestureEdge(for: host.view)
    host.view.addGestureRecognizer(edgeGesture)
    updateInterception()
  }

  func setVisible(_ visible: Bool) {
    self.visible = visible
    updateInterception()
  }

  func setEnabled(_ enabled: Bool) {
    guard self.enabled != enabled else { return }
    if !enabled, gestureStarted {
      emit(
        phase: "cancel",
        progress: lastProgress,
        source: "gesture",
        touch: lastTouch
      )
      resetGesture()
    }
    self.enabled = enabled
    updateInterception()
  }

  func destroy() {
    if gestureStarted {
      emit(
        phase: "cancel",
        progress: lastProgress,
        source: "gesture",
        touch: lastTouch
      )
    }
    enabled = false
    visible = false
    resetGesture()
    updateInterception()
    if let view = edgeGesture.view {
      view.removeGestureRecognizer(edgeGesture)
    }
    lynxView = nil
  }

  func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
    guard enabled,
          visible,
          let host,
          host.viewIfLoaded?.window != nil,
          host.transitionCoordinator == nil else {
      return false
    }
    return true
  }

  private func updateInterception() {
    guard let host else { return }
    let shouldIntercept = enabled && visible
    updateGestureEdge(for: host.view)
    edgeGesture.isEnabled = shouldIntercept
    if shouldIntercept {
      suspendNativeInteractivePopIfNeeded()
      installNavigationButtonIfNeeded()
    } else {
      restoreNativeInteractivePop()
      restoreNavigationButton()
    }
  }

  private func updateGestureEdge(for view: UIView) {
    let direction = UIView.userInterfaceLayoutDirection(
      for: view.semanticContentAttribute
    )
    edgeGesture.edges = direction == .rightToLeft ? .right : .left
  }

  private func suspendNativeInteractivePopIfNeeded() {
    guard let gesture = host?.navigationController?.interactivePopGestureRecognizer else {
      restoreNativeInteractivePop()
      return
    }
    if capturedNativePopGesture !== gesture {
      restoreNativeInteractivePop()
      capturedNativePopGesture = gesture
      nativePopWasEnabled = gesture.isEnabled
    }
    gesture.isEnabled = false
  }

  private func restoreNativeInteractivePop() {
    if let gesture = capturedNativePopGesture,
       let wasEnabled = nativePopWasEnabled {
      gesture.isEnabled = wasEnabled
    }
    capturedNativePopGesture = nil
    nativePopWasEnabled = nil
  }

  private func installNavigationButtonIfNeeded() {
    guard !installedBackButton,
          let host,
          let navigation = host.navigationController,
          navigation.viewControllers.first !== host else {
      return
    }
    let item = host.navigationItem
    savedLeftBarButtonItems = item.leftBarButtonItems
    savedHidesBackButton = item.hidesBackButton
    let button = UIBarButtonItem(
      image: UIImage(systemName: "chevron.backward"),
      style: .plain,
      target: self,
      action: #selector(handleNavigationButton)
    )
    button.accessibilityLabel = NSLocalizedString("Back", comment: "Native back button")
    item.hidesBackButton = true
    item.leftBarButtonItems = [button]
    installedBackButton = true
  }

  private func restoreNavigationButton() {
    guard installedBackButton, let host else { return }
    host.navigationItem.leftBarButtonItems = savedLeftBarButtonItems
    host.navigationItem.hidesBackButton = savedHidesBackButton ?? false
    savedLeftBarButtonItems = nil
    savedHidesBackButton = nil
    installedBackButton = false
  }

  @objc private func handleNavigationButton() {
    guard enabled else { return }
    emit(
      phase: "start",
      progress: 0,
      source: "button",
      touch: .zero,
      edge: "none"
    )
    emit(
      phase: "commit",
      progress: 1,
      source: "button",
      touch: .zero,
      edge: "none"
    )
  }

  @objc private func handleEdgeGesture(_ gesture: UIScreenEdgePanGestureRecognizer) {
    guard let view = gesture.view else { return }
    let multiplier: CGFloat = gesture.edges.contains(.right) ? -1 : 1
    let width = max(view.bounds.width, 1)
    let translation = gesture.translation(in: view).x * multiplier
    let progress = min(max(translation / width, 0), 1)
    lastTouch = gesture.location(in: view)

    switch gesture.state {
    case .began:
      gestureStarted = true
      lastProgress = progress
      emit(
        phase: "start",
        progress: progress,
        source: "gesture",
        touch: lastTouch
      )
    case .changed:
      guard gestureStarted else { return }
      lastProgress = progress
      emit(
        phase: "progress",
        progress: progress,
        source: "gesture",
        touch: lastTouch
      )
    case .ended:
      guard gestureStarted else { return }
      lastProgress = progress
      let velocity = gesture.velocity(in: view).x * multiplier
      let shouldCommit = velocity > 600 || (velocity >= 0 && progress >= 0.35)
      emit(
        phase: shouldCommit ? "commit" : "cancel",
        progress: shouldCommit ? 1 : progress,
        source: "gesture",
        touch: lastTouch
      )
      resetGesture()
    case .cancelled, .failed:
      guard gestureStarted else { return }
      emit(
        phase: "cancel",
        progress: lastProgress,
        source: "gesture",
        touch: lastTouch
      )
      resetGesture()
    default:
      break
    }
  }

  private func resetGesture() {
    gestureStarted = false
    lastProgress = 0
    lastTouch = .zero
  }

  private func emit(
    phase: String,
    progress: CGFloat,
    source: String,
    touch: CGPoint,
    edge: String? = nil
  ) {
    let resolvedEdge = edge ?? (edgeGesture.edges.contains(.right) ? "right" : "left")
    let payload: [String: Any] = [
      "platform": "ios",
      "phase": phase,
      "progress": Double(min(max(progress, 0), 1)),
      "source": source,
      "edge": resolvedEdge,
      "touchX": Double(touch.x),
      "touchY": Double(touch.y),
    ]
    lynxView?.sendGlobalEvent(Self.eventName, withParams: [payload])
  }
}

@objcMembers
final class NativeBackModule: NSObject, LynxModule {
  static let name = "NativeBackModule"
  static let methodLookup = [
    "setEnabled": "setEnabled:callback:",
  ]

  private weak var controller: NativeBackController?

  @objc(initWithParam:)
  init(param: Any) {
    controller = param as? NativeBackController
    super.init()
  }

  override init() {
    super.init()
  }

  func setEnabled(_ enabled: Bool, callback: @escaping LynxCallbackBlock) {
    DispatchQueue.main.async { [weak self] in
      guard let controller = self?.controller else {
        callback("Native back has no UIViewController host")
        return
      }
      controller.setEnabled(enabled)
      callback("")
    }
  }

  func destroy() {
    DispatchQueue.main.async { [weak controller] in
      controller?.setEnabled(false)
    }
  }
}
