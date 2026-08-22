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

/// Reloads from the embedded bundle when the bundle bytes cannot be fetched or
/// parsed (dev server offline, broken OTA cache). JS runtime errors stay
/// visible during development. Runs at most once: if the embedded bundle
/// itself fails, the error keeps surfacing.
private final class EmbeddedBundleFallback: NSObject, LynxViewLifecycle {
  private static let bundleLoadFailureSubcodes: Set<Int> = [10203, 10204, 10205]

  private let onBundleLoadFailure: () -> Void
  private var hasFallenBack = false

  init(onBundleLoadFailure: @escaping () -> Void) {
    self.onBundleLoadFailure = onBundleLoadFailure
  }

  func lynxView(_ view: LynxView, didRecieveError error: Error) {
    guard let lynxError = error as? LynxError,
          lynxError.isFatal,
          Self.bundleLoadFailureSubcodes.contains(lynxError.getSubCode()) else {
      return
    }
    // Template providers may complete on a background URLSession/file queue;
    // keep the one-shot guard and LynxView reload on the main thread.
    DispatchQueue.main.async { [weak self] in
      guard let self, !self.hasFallenBack else { return }
      self.hasFallenBack = true
      self.onBundleLoadFailure()
    }
  }
}

/// Reveals the content over the present backdrop once its first screen has
/// been painted (see PresentBackdrop for the choreography timing).
private final class PresentScreenObserver: NSObject, LynxViewLifecycle {
  private let onFirstScreen: () -> Void

  init(onFirstScreen: @escaping () -> Void) {
    self.onFirstScreen = onFirstScreen
  }

  func lynxViewDidFirstScreen(_ view: LynxView) {
    onFirstScreen()
  }
}

/// Reusable native host for both the storyboard root and routed Lynx bundles.
class LynxPageViewController: UIViewController, LynxDeviceStatusBarHost {
  private let bundleRepository = LynxBundleRepository()
  private let bundleName: String
  private let route: [String: Any]?
  private var presentBackdrop: PresentBackdrop?
  private let presentIOSSwipeDownEnabled: Bool
  /// Correlates this page with its opener's pending openForResult callback.
  let routeResultToken: String?

  var routeAnimation: NativeRouteAnimation {
    NativeRouteAnimation(rawValue: route?["animation"] as? String ?? "") ?? .standard
  }
  private var nativeStatusBarStyle: NativeStatusBarStyle
  private var lynxView: LynxView?
  private var embeddedFallback: EmbeddedBundleFallback?
  private var presentScreenObserver: PresentScreenObserver?
  private var hasLoadedInitialBundle = false
  private var canUpdateTemplate = false
  private var lastSafeAreaInsets: UIEdgeInsets?

  #if DEBUG
  private var developmentButton: UIButton?
  private var isDraggingDevelopmentButton = false
  private var developmentButtonDragOrigin: CGPoint = .zero
  #endif

  init(
    bundleName: String,
    route: [String: Any]?,
    snapshot: UIImage?,
    statusBarStyle: NativeStatusBarStyle,
    presentScrimColor: UIColor? = nil,
    presentBackdropTransition: Bool = true,
    presentEnterAnimation: PresentContentAnimationOptions = .standard,
    presentExitAnimation: PresentContentAnimationOptions = .standard,
    presentIOSSwipeDownEnabled: Bool = false,
    routeResultToken: String? = nil
  ) {
    self.bundleName = bundleName
    self.route = route
    self.routeResultToken = routeResultToken
    self.presentIOSSwipeDownEnabled = presentIOSSwipeDownEnabled
    presentBackdrop = snapshot.map {
      PresentBackdrop(
        image: $0,
        scrimColor: presentScrimColor ?? PresentBackdrop.defaultScrimColor,
        playsBackdropTransition: presentBackdropTransition,
        enterAnimation: presentEnterAnimation,
        exitAnimation: presentExitAnimation
      )
    }
    nativeStatusBarStyle = statusBarStyle
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    bundleName = "main"
    route = nil
    presentBackdrop = nil
    presentIOSSwipeDownEnabled = false
    routeResultToken = nil
    nativeStatusBarStyle = .darkContent
    super.init(coder: coder)
  }

  deinit {
    // Safety net: every real close path delivers from viewDidDisappear, but
    // a page dropped without a full disappearance pass must still resolve.
    if let routeResultToken {
      AppRouteHandler.completeRouteResult(token: routeResultToken)
    }
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    // Behind the shrinking snapshot the margins stay solid black, like iOS'
    // own present chrome; plain pages keep the light page background.
    view.backgroundColor = presentBackdrop != nil
      ? .black
      : UIColor(red: 247 / 255, green: 247 / 255, blue: 251 / 255, alpha: 1)
    if let backdrop = presentBackdrop {
      // The snapshot fills the view from the first frame, before the Lynx
      // content exists, so the push with no animation is imperceptible.
      backdrop.view.frame = view.bounds
      backdrop.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      view.addSubview(backdrop.view)
      backdrop.scrim.frame = view.bounds
      backdrop.scrim.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      view.addSubview(backdrop.scrim)
    }

    // The explicit host adapter records the exact module registry installed
    // on this view; the autolinked native component owns only WebView/RPC.
    let config = WebviewModuleBridgeHostAdapter.makeConfig(
      provider: bundleRepository
    )
    // Back, Router and the other workspace modules come from autolink/*.
    // Router's host navigation policy installs once in AppDelegate.
    LynxGeneratedLibraryRegistry().setup(config)
    let lynxView = LynxView { builder in
      builder.config = config
      builder.genericResourceFetcher = AppGenericResourceFetcher()
      builder.enableGenericResourceFetcher = .true
      builder.screenSize = self.view.frame.size
      builder.fontScale = 1.0
    }
    WebviewModuleBridgeHostAdapter.attach(config, to: lynxView)

    lynxView.backgroundColor = presentBackdrop != nil ? .clear : view.backgroundColor
    lynxView.isOpaque = presentBackdrop == nil
    lynxView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    lynxView.frame = view.bounds
    lynxView.preferredLayoutWidth = self.view.frame.size.width
    lynxView.preferredLayoutHeight = self.view.frame.size.height
    lynxView.layoutWidthMode = .exact
    lynxView.layoutHeightMode = .exact
    view.addSubview(lynxView)
    self.lynxView = lynxView

    // A dev server or OTA cache that cannot serve the bundle must not leave a
    // white screen; render the embedded bundle instead (once).
    let fallback = EmbeddedBundleFallback { [weak self] in
      guard let self else { return }
      self.loadBundle(fromURL: self.bundleRepository.embeddedURL(forBundle: self.bundleName))
    }
    lynxView.addLifecycleClient(fallback)
    embeddedFallback = fallback

    if let backdrop = presentBackdrop {
      let observer = PresentScreenObserver { [weak self] in
        guard let self, let content = self.lynxView else { return }
        backdrop.playPresent(content: content)
      }
      lynxView.addLifecycleClient(observer)
      presentScreenObserver = observer
      backdrop.prepare(content: lynxView)
    }

    #if DEBUG
    if route == nil {
      installDevelopmentButton()
    }
    #endif
  }

  override func viewSafeAreaInsetsDidChange() {
    super.viewSafeAreaInsetsDidChange()
    loadInitialBundleIfReady()
    updateNativeEnvironmentIfNeeded()
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    // `frame` is undefined while a view has a non-identity transform. The
    // present/dismiss choreography transforms the Lynx view, so updating its
    // frame during an animation can make the bottom sheet jump. Lay it out
    // through bounds and center, which remain stable under transforms.
    lynxView?.bounds = CGRect(origin: .zero, size: view.bounds.size)
    lynxView?.center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
    lynxView?.preferredLayoutWidth = view.bounds.width
    lynxView?.preferredLayoutHeight = view.bounds.height
    loadInitialBundleIfReady()
    updateNativeEnvironmentIfNeeded()
    #if DEBUG
    layoutDevelopmentButton()
    #endif
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    // A nested push/pop temporarily reparents this page inside UIKit's
    // transition container. Reapply the dynamic screen-concentric clipping
    // before the snapshot becomes visible again.
    presentBackdrop?.restoreCornerClipping()
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    // Reapply once more after the navigation transition has installed the
    // page back in its final container; this also covers cancelled gestures.
    presentBackdrop?.restoreCornerClipping()
    loadInitialBundleIfReady()
  }

  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    // Being covered by a nested push keeps this page in the navigation
    // stack; only a real removal (pop, dismiss choreography) resolves the
    // opener's pending openForResult here. deinit is the safety net.
    let stillInStack = navigationController?.viewControllers.contains(self) ?? false
    if !stillInStack, let routeResultToken {
      AppRouteHandler.completeRouteResult(token: routeResultToken)
    }
  }

  override var preferredStatusBarStyle: UIStatusBarStyle {
    nativeStatusBarStyle.uiStyle
  }

  func setLynxStatusBarStyle(_ rawStyle: String) {
    guard let style = NativeStatusBarStyle(rawValue: rawStyle) else { return }
    nativeStatusBarStyle = style
    setNeedsStatusBarAppearanceUpdate()
  }

  /// Captures the currently resolved screen-concentric snapshot radius before
  /// another route asks UINavigationController to move this page through a
  /// transition container.
  func preservePresentBackdropCornerClipping() {
    presentBackdrop?.preserveCornerClipping()
  }

  var canBeginPresentSwipeDown: Bool {
    presentIOSSwipeDownEnabled &&
      routeAnimation == .present &&
      presentBackdrop?.canBeginInteractiveDismiss == true
  }

  func beginPresentSwipeDown() -> Bool {
    guard canBeginPresentSwipeDown,
          let backdrop = presentBackdrop,
          let content = lynxView else { return false }
    return backdrop.beginInteractiveDismiss(content: content)
  }

  func updatePresentSwipeDown(progress: CGFloat) {
    guard let backdrop = presentBackdrop, let content = lynxView else { return }
    backdrop.updateInteractiveDismiss(progress: progress, content: content)
  }

  func cancelPresentSwipeDown() {
    guard let backdrop = presentBackdrop, let content = lynxView else { return }
    backdrop.cancelInteractiveDismiss(content: content)
  }

  func finishPresentSwipeDown(completion: @escaping () -> Void) {
    guard let backdrop = presentBackdrop, let content = lynxView else {
      completion()
      return
    }
    backdrop.finishInteractiveDismiss(content: content, completion: completion)
  }

  /// Closes a present route through the reverse choreography (see
  /// PresentBackdrop); non-present routes call the completion immediately.
  func playDismissChoreography(completion: @escaping () -> Void) {
    guard let backdrop = presentBackdrop, let content = lynxView else {
      completion()
      return
    }
    backdrop.playDismiss(content: content, completion: completion)
  }

  private func loadInitialBundleIfReady() {
    guard !hasLoadedInitialBundle, view.window != nil else { return }
    hasLoadedInitialBundle = true
    loadBundle(fromURL: bundleRepository.url(forBundle: bundleName))

    guard bundleName == "main" else { return }
    bundleRepository.checkForUpdate { [weak self] updated in
      guard updated else { return }
      DispatchQueue.main.async {
        guard let self else { return }
        self.loadBundle(fromURL: self.bundleRepository.cachedURL())
      }
    }
  }

  private func loadBundle(fromURL url: String) {
    let safeAreaInsets = view.safeAreaInsets
    lastSafeAreaInsets = safeAreaInsets
    lynxView?.loadTemplate(
      fromURL: url,
      initData: nativeEnvironmentData(safeAreaInsets)
    )
    canUpdateTemplate = true
  }

  private func updateNativeEnvironmentIfNeeded() {
    let safeAreaInsets = view.safeAreaInsets
    guard canUpdateTemplate,
          !sameInsets(safeAreaInsets, lastSafeAreaInsets) else {
      return
    }

    lastSafeAreaInsets = safeAreaInsets
    let updateMeta = LynxUpdateMeta()
    updateMeta.data = nativeEnvironmentData(safeAreaInsets)
    lynxView?.updateMetaData(updateMeta)
  }

  private func nativeEnvironmentData(_ insets: UIEdgeInsets) -> LynxTemplateData {
    var additionalData: [String: Any] = [:]
    if let route {
      additionalData["route"] = route
    }
    return LynxDeviceTemplateData(insets, additionalData)
  }

  private func sameInsets(_ lhs: UIEdgeInsets, _ rhs: UIEdgeInsets?) -> Bool {
    guard let rhs else { return false }
    return lhs.top == rhs.top
      && lhs.right == rhs.right
      && lhs.bottom == rhs.bottom
      && lhs.left == rhs.left
  }

  #if DEBUG
  private enum DevelopmentButton {
    static let size = CGSize(width: 54, height: 34)
    static let margin: CGFloat = 12
    static let topOffset: CGFloat = 10
    static let centerXKey = "developmentButtonCenterX"
    static let centerYKey = "developmentButtonCenterY"
  }

  private func installDevelopmentButton() {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setTitle("DEV", for: .normal)
    button.setTitleColor(.white, for: .normal)
    button.titleLabel?.font = .boldSystemFont(ofSize: 12)
    button.backgroundColor = UIColor(
      red: 43 / 255,
      green: 99 / 255,
      blue: 241 / 255,
      alpha: 0.9
    )
    button.layer.cornerRadius = 17
    button.layer.borderColor = UIColor.white.withAlphaComponent(0.35).cgColor
    button.layer.borderWidth = 1
    button.addTarget(
      self,
      action: #selector(openDevelopmentSettings),
      for: .touchUpInside
    )
    // The pan recognizer only wins once the finger travels far enough, so taps
    // still reach .touchUpInside while drags reposition the pill.
    button.addGestureRecognizer(
      UIPanGestureRecognizer(target: self, action: #selector(dragDevelopmentButton(_:)))
    )
    view.addSubview(button)
    NSLayoutConstraint.activate([
      button.widthAnchor.constraint(equalToConstant: DevelopmentButton.size.width),
      button.heightAnchor.constraint(equalToConstant: DevelopmentButton.size.height),
    ])
    developmentButton = button
  }

  private func layoutDevelopmentButton() {
    guard let button = developmentButton, !isDraggingDevelopmentButton else { return }
    let bounds = view.bounds
    guard bounds.width > 0, bounds.height > 0 else { return }
    let defaults = UserDefaults.standard
    if let storedX = defaults.object(forKey: DevelopmentButton.centerXKey) as? Double,
       let storedY = defaults.object(forKey: DevelopmentButton.centerYKey) as? Double {
      button.center = clampedDevelopmentButtonCenter(CGPoint(x: storedX, y: storedY))
    } else {
      button.center = clampedDevelopmentButtonCenter(
        CGPoint(
          x: bounds.maxX - view.safeAreaInsets.right - DevelopmentButton.margin
            - DevelopmentButton.size.width / 2,
          y: view.safeAreaInsets.top + DevelopmentButton.topOffset
            + DevelopmentButton.size.height / 2
        )
      )
    }
  }

  private func clampedDevelopmentButtonCenter(_ center: CGPoint) -> CGPoint {
    let safeArea = view.safeAreaInsets
    let minX = safeArea.left + DevelopmentButton.size.width / 2
    let minY = safeArea.top + DevelopmentButton.size.height / 2
    let maxX = max(view.bounds.width - safeArea.right - DevelopmentButton.size.width / 2, minX)
    let maxY = max(view.bounds.height - safeArea.bottom - DevelopmentButton.size.height / 2, minY)
    return CGPoint(
      x: min(max(center.x, minX), maxX),
      y: min(max(center.y, minY), maxY)
    )
  }

  @objc private func dragDevelopmentButton(_ gesture: UIPanGestureRecognizer) {
    guard let button = developmentButton else { return }
    switch gesture.state {
    case .began:
      isDraggingDevelopmentButton = true
      developmentButtonDragOrigin = button.center
    case .changed:
      let translation = gesture.translation(in: view)
      button.center = clampedDevelopmentButtonCenter(
        CGPoint(
          x: developmentButtonDragOrigin.x + translation.x,
          y: developmentButtonDragOrigin.y + translation.y
        )
      )
    case .ended:
      isDraggingDevelopmentButton = false
      let defaults = UserDefaults.standard
      defaults.set(Double(button.center.x), forKey: DevelopmentButton.centerXKey)
      defaults.set(Double(button.center.y), forKey: DevelopmentButton.centerYKey)
    case .cancelled:
      isDraggingDevelopmentButton = false
      layoutDevelopmentButton()
    default:
      break
    }
  }

  @objc private func openDevelopmentSettings() {
    let settings = DebugSettingsViewController()
    settings.onSettingsChanged = { [weak self] in
      self?.reloadForDevelopmentSettings()
    }
    let navigation = UINavigationController(rootViewController: settings)
    navigation.modalPresentationStyle = .formSheet
    present(navigation, animated: true)
  }

  private func reloadForDevelopmentSettings() {
    canUpdateTemplate = false
    loadBundle(fromURL: bundleRepository.url(forBundle: bundleName))
  }
  #endif
}
