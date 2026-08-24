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

/// Kicks the OTA preload 200ms after the page's first screen (bundles whose
/// package.json `lynxBundle.downloadAt` listed this one).
private final class BundlePreloadObserver: NSObject, LynxViewLifecycle {
  private let onFirstScreen: () -> Void

  init(onFirstScreen: @escaping () -> Void) {
    self.onFirstScreen = onFirstScreen
  }

  func lynxViewDidFirstScreen(_ view: LynxView) {
    onFirstScreen()
  }
}

/// Relays intrinsic-size changes from a content-height dialog LynxView back to
/// its native overlay so only that view follows the keyboard.
private final class DialogLayoutObserver: NSObject, LynxViewLifecycle {
  private let onLayoutChange: () -> Void

  init(onLayoutChange: @escaping () -> Void) {
    self.onLayoutChange = onLayoutChange
  }

  func lynxViewDidFirstScreen(_ view: LynxView) {
    onLayoutChange()
  }

  func lynxViewDidChangeIntrinsicContentSize(_ view: LynxView) {
    onLayoutChange()
  }
}

/// Reusable native host for both the storyboard root and routed Lynx bundles.
class LynxPageViewController: UIViewController, LynxDeviceStatusBarHost,
  UIGestureRecognizerDelegate {
  private let bundleRepository = LynxBundleRepository()
  private let bundleName: String
  private let route: [String: Any]?
  private var presentBackdrop: PresentBackdrop?
  private let presentIOSSwipeDownEnabled: Bool
  private let presentDragDownToDismissEnabled: Bool
  /// Correlates this page with its opener's pending openForResult callback.
  let routeResultToken: String?

  var routeAnimation: NativeRouteAnimation {
    NativeRouteAnimation(rawValue: route?["animation"] as? String ?? "") ?? .standard
  }
  var isInputDialogRoute: Bool {
    route?["presentation"] as? String == NativeRoutePresentation.inputDialog.rawValue
  }
  /// Overlay routes carry the snapshot backdrop and its choreography.
  var isOverlayRoute: Bool {
    route?["presentation"] as? String == NativeRoutePresentation.overlay.rawValue
  }
  private var nativeStatusBarStyle: NativeStatusBarStyle
  private var lynxView: LynxView?
  private var embeddedFallback: EmbeddedBundleFallback?
  private var presentScreenObserver: PresentScreenObserver?
  private var bundlePreloadObserver: BundlePreloadObserver?
  private var dialogLayoutObserver: DialogLayoutObserver?
  private var hasLoadedInitialBundle = false
  /// Loading cover over opaque pages while the OTA entry gate resolves.
  private var entrySplashView: UIView?
  private var canUpdateTemplate = false
  private var lastSafeAreaInsets: UIEdgeInsets?
  private var lastColorScheme: String?
  private var lastLocale: String?
  private var dialogKeyboardOverlap: CGFloat = 0
  private var dialogContentInsetBottom: CGFloat = 0
  private var lastDialogContentInsetBottom: CGFloat?
  private var dialogHasPresentedKeyboard = false
  private var dialogKeyboardTransitionInProgress = false
  private var dialogDismissInProgress = false
  private var pendingDialogDismiss: (() -> Void)?
  private var dialogDismissFallback: DispatchWorkItem?
  private lazy var presentDragDownGesture: UIPanGestureRecognizer = {
    let gesture = UIPanGestureRecognizer(
      target: self,
      action: #selector(handlePresentDragDown(_:))
    )
    gesture.maximumNumberOfTouches = 1
    gesture.cancelsTouchesInView = true
    gesture.delaysTouchesBegan = false
    gesture.delegate = self
    return gesture
  }()

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
    presentDragDownToDismissEnabled: Bool = false,
    routeResultToken: String? = nil
  ) {
    self.bundleName = bundleName
    self.route = route
    self.routeResultToken = routeResultToken
    self.presentIOSSwipeDownEnabled = presentIOSSwipeDownEnabled
    self.presentDragDownToDismissEnabled = presentDragDownToDismissEnabled
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
    presentDragDownToDismissEnabled = false
    routeResultToken = nil
    nativeStatusBarStyle = .darkContent
    super.init(coder: coder)
  }

  deinit {
    dialogDismissFallback?.cancel()
    NotificationCenter.default.removeObserver(self)
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
    view.backgroundColor = isInputDialogRoute
      ? .clear
      : (presentBackdrop != nil
        ? .black
        : .systemBackground)
    if route == nil {
      nativeStatusBarStyle = nativeColorScheme == "dark" ? .lightContent : .darkContent
    }
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(nativeLocaleDidChange),
      name: NSLocale.currentLocaleDidChangeNotification,
      object: nil
    )
    if isInputDialogRoute {
      let dimmingControl = UIControl(frame: view.bounds)
      dimmingControl.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      dimmingControl.backgroundColor = UIColor.black.withAlphaComponent(0.45)
      dimmingControl.addTarget(
        self,
        action: #selector(dialogBackdropTapped),
        for: .touchUpInside
      )
      view.addSubview(dimmingControl)
      NotificationCenter.default.addObserver(
        self,
        selector: #selector(dialogKeyboardWillChangeFrame(_:)),
        name: UIResponder.keyboardWillChangeFrameNotification,
        object: nil
      )
    }
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

    lynxView.backgroundColor = presentBackdrop != nil || isInputDialogRoute
      ? .clear
      : view.backgroundColor
    lynxView.isOpaque = presentBackdrop == nil && !isInputDialogRoute
    lynxView.autoresizingMask = isInputDialogRoute
      ? [.flexibleWidth]
      : [.flexibleWidth, .flexibleHeight]
    lynxView.frame = view.bounds
    lynxView.preferredLayoutWidth = self.view.frame.size.width
    lynxView.preferredLayoutHeight = self.view.frame.size.height
    lynxView.layoutWidthMode = .exact
    if isInputDialogRoute {
      lynxView.preferredMaxLayoutHeight = self.view.frame.size.height
      lynxView.layoutHeightMode = .max
    } else {
      lynxView.layoutHeightMode = .exact
    }
    view.addSubview(lynxView)
    self.lynxView = lynxView
    if presentDragDownToDismissEnabled {
      // This recognizer is external to Lynx. If it wins UIKit's gesture
      // arbitration, Lynx receives touch-cancel and native owns the same
      // pointer until end/cancel. Page elements that explicitly block native
      // gestures keep their own interaction instead.
      view.addGestureRecognizer(presentDragDownGesture)
    }

    // A dev server or OTA cache that cannot serve the bundle must not leave a
    // white screen; render the embedded bundle instead (once).
    let fallback = EmbeddedBundleFallback { [weak self] in
      guard let self else { return }
      self.loadBundle(fromURL: self.bundleRepository.embeddedURL(forBundle: self.bundleName))
    }
    lynxView.addLifecycleClient(fallback)
    embeddedFallback = fallback

    let preloadObserver = BundlePreloadObserver { [weak self] in
      guard let self else { return }
      self.bundleRepository.schedulePreloadAfterFirstScreen(for: self.bundleName)
    }
    lynxView.addLifecycleClient(preloadObserver)
    bundlePreloadObserver = preloadObserver

    if let backdrop = presentBackdrop {
      let observer = PresentScreenObserver { [weak self] in
        guard let self, let content = self.lynxView else { return }
        backdrop.playPresent(content: content)
      }
      lynxView.addLifecycleClient(observer)
      presentScreenObserver = observer
      backdrop.prepare(content: lynxView)
    }
    if isInputDialogRoute {
      let observer = DialogLayoutObserver { [weak self] in
        DispatchQueue.main.async {
          self?.layoutDialogLynxView()
        }
      }
      lynxView.addLifecycleClient(observer)
      dialogLayoutObserver = observer
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

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)
    guard previousTraitCollection?.hasDifferentColorAppearance(
      comparedTo: traitCollection
    ) ?? true else { return }

    if !isInputDialogRoute, presentBackdrop == nil {
      view.backgroundColor = .systemBackground
      lynxView?.backgroundColor = .systemBackground
    }
    if route == nil {
      nativeStatusBarStyle = nativeColorScheme == "dark" ? .lightContent : .darkContent
      setNeedsStatusBarAppearanceUpdate()
    }
    updateNativeEnvironmentIfNeeded()
  }

  @objc private func nativeLocaleDidChange() {
    updateNativeEnvironmentIfNeeded()
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    // `frame` is undefined while a view has a non-identity transform. The
    // present/dismiss choreography transforms the Lynx view, so updating its
    // frame during an animation can make the bottom sheet jump. Lay it out
    // through bounds and center, which remain stable under transforms.
    if isInputDialogRoute {
      layoutDialogLynxView()
    } else {
      lynxView?.bounds = CGRect(origin: .zero, size: view.bounds.size)
      lynxView?.center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
      lynxView?.preferredLayoutWidth = view.bounds.width
      lynxView?.preferredLayoutHeight = view.bounds.height
    }
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
    let routeWasRemoved = isInputDialogRoute
      ? (isBeingDismissed || presentingViewController == nil)
      : !stillInStack
    if routeWasRemoved, let routeResultToken {
      AppRouteHandler.completeRouteResult(token: routeResultToken)
    }
  }

  /// Hides the dialog's keyboard first; the supplied close action runs only
  /// after UIKit has completed the keyboard transition.
  func requestDialogDismiss(_ close: @escaping () -> Void) {
    guard isInputDialogRoute, !dialogDismissInProgress else { return }
    if pendingDialogDismiss == nil {
      pendingDialogDismiss = close
    }
    let resignedEditor = view.endEditing(true)
    if dialogKeyboardOverlap <= 0 && !dialogKeyboardTransitionInProgress && !resignedEditor {
      completeDialogDismiss()
      return
    }
    dialogDismissFallback?.cancel()
    let fallback = DispatchWorkItem { [weak self] in
      self?.completeDialogDismiss()
    }
    dialogDismissFallback = fallback
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: fallback)
  }

  @objc private func dialogBackdropTapped() {
    requestDialogDismiss { [weak self] in
      self?.dismiss(animated: false)
    }
  }

  @objc private func dialogKeyboardWillChangeFrame(_ notification: Notification) {
    guard isInputDialogRoute,
          let userInfo = notification.userInfo,
          let endValue = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue else {
      return
    }
    let endFrame = view.convert(endValue.cgRectValue, from: nil)
    let overlap = max(view.bounds.intersection(endFrame).height, 0)
    let duration = (userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?
      .doubleValue ?? 0.25
    let curve = (userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber)?
      .uintValue ?? UInt(UIView.AnimationCurve.easeInOut.rawValue)
    dialogKeyboardTransitionInProgress = true
    dialogKeyboardOverlap = overlap
    // Keep the Lynx surface attached to the physical screen bottom. Matching
    // route padding leaves its interactive content above the keyboard while
    // its own background paints underneath the complete keyboard material.
    dialogContentInsetBottom = overlap
    if overlap > 0 {
      dialogHasPresentedKeyboard = true
    }
    updateNativeEnvironmentIfNeeded()
    UIView.animate(
      withDuration: duration,
      delay: 0,
      options: UIView.AnimationOptions(rawValue: curve << 16),
      animations: { [weak self] in
        self?.layoutDialogLynxView()
      },
      completion: { [weak self] _ in
        guard let self else { return }
        self.dialogKeyboardTransitionInProgress = false
        guard self.dialogHasPresentedKeyboard,
              self.dialogKeyboardOverlap <= 0 else { return }
        if self.pendingDialogDismiss == nil {
          self.pendingDialogDismiss = { [weak self] in
            self?.dismiss(animated: false)
          }
        }
        self.completeDialogDismiss()
      }
    )
  }

  private func layoutDialogLynxView() {
    guard isInputDialogRoute, let lynxView else { return }
    let extendedBottom = view.bounds.height
    let availableHeight = max(extendedBottom, 1)
    lynxView.preferredLayoutWidth = view.bounds.width
    lynxView.preferredMaxLayoutHeight = availableHeight
    lynxView.layoutWidthMode = .exact
    lynxView.layoutHeightMode = .max

    let intrinsicHeight = lynxView.intrinsicContentSize.height
    let candidateHeight = intrinsicHeight.isFinite && intrinsicHeight > 0
      ? intrinsicHeight
      : lynxView.bounds.height
    let height = min(max(candidateHeight, 1), availableHeight)
    lynxView.bounds = CGRect(x: 0, y: 0, width: view.bounds.width, height: height)
    lynxView.center = CGPoint(
      x: view.bounds.midX,
      y: extendedBottom - height / 2
    )
  }

  private func completeDialogDismiss() {
    guard !dialogDismissInProgress, let close = pendingDialogDismiss else { return }
    dialogDismissInProgress = true
    dialogDismissFallback?.cancel()
    dialogDismissFallback = nil
    pendingDialogDismiss = nil
    close()
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

  private var canBeginPresentInteractiveDismiss: Bool {
    isOverlayRoute &&
      presentBackdrop?.canBeginInteractiveDismiss == true
  }

  var canBeginPresentSwipeDown: Bool {
    presentIOSSwipeDownEnabled && canBeginPresentInteractiveDismiss
  }

  private var canBeginPresentDragDown: Bool {
    presentDragDownToDismissEnabled && canBeginPresentInteractiveDismiss
  }

  func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
    guard gestureRecognizer === presentDragDownGesture,
          canBeginPresentDragDown else { return false }
    let velocity = presentDragDownGesture.velocity(in: view)
    return velocity.y > 0 && abs(velocity.y) > abs(velocity.x)
  }

  @objc private func handlePresentDragDown(_ gesture: UIPanGestureRecognizer) {
    let height = max(view.bounds.height, 1)
    let progress = min(max(gesture.translation(in: view).y / height, 0), 1)

    switch gesture.state {
    case .began:
      _ = beginPresentSwipeDown()
    case .changed:
      updatePresentSwipeDown(progress: progress)
    case .ended:
      let velocity = gesture.velocity(in: view).y
      if progress >= 0.25 || velocity >= 800 {
        finishPresentSwipeDown { [weak self] in
          guard let self,
                let navigation = self.navigationController,
                navigation.topViewController === self else { return }
          navigation.popViewController(animated: false)
        }
      } else {
        cancelPresentSwipeDown()
      }
    case .cancelled, .failed:
      cancelPresentSwipeDown()
    default:
      break
    }
  }

  func beginPresentSwipeDown() -> Bool {
    guard canBeginPresentInteractiveDismiss,
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
    showEntrySplashIfNeeded()

    // The OTA entry gate: dev override, verified cache, or embedded asset —
    // a changed bundle downloads (bounded) before the first render instead
    // of reloading afterwards.
    bundleRepository.resolveEntry(forBundle: bundleName) { [weak self] url in
      guard let self else { return }
      self.hideEntrySplash()
      self.loadBundle(fromURL: url)
    }
  }

  /// Plain loading cover for opaque pages while the OTA entry gate resolves.
  private func showEntrySplashIfNeeded() {
    guard presentBackdrop == nil, !isInputDialogRoute, entrySplashView == nil else {
      return
    }
    let splash = UIView(frame: view.bounds)
    splash.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    splash.backgroundColor = view.backgroundColor
    let spinner = UIActivityIndicatorView(style: .medium)
    spinner.center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
    spinner.autoresizingMask = [
      .flexibleLeftMargin, .flexibleRightMargin,
      .flexibleTopMargin, .flexibleBottomMargin,
    ]
    spinner.startAnimating()
    splash.addSubview(spinner)
    view.addSubview(splash)
    entrySplashView = splash
  }

  private func hideEntrySplash() {
    entrySplashView?.removeFromSuperview()
    entrySplashView = nil
  }

  private func loadBundle(fromURL url: String) {
    let safeAreaInsets = view.safeAreaInsets
    lastSafeAreaInsets = safeAreaInsets
    lastColorScheme = nativeColorScheme
    lastLocale = nativeLocale
    lastDialogContentInsetBottom = dialogContentInsetBottom
    lynxView?.loadTemplate(
      fromURL: url,
      initData: nativeEnvironmentData(safeAreaInsets)
    )
    canUpdateTemplate = true
  }

  private func updateNativeEnvironmentIfNeeded() {
    let safeAreaInsets = view.safeAreaInsets
    let colorScheme = nativeColorScheme
    let locale = nativeLocale
    let contentInsetBottom = dialogContentInsetBottom
    guard canUpdateTemplate,
          (!sameInsets(safeAreaInsets, lastSafeAreaInsets)
            || colorScheme != lastColorScheme
            || locale != lastLocale
            || contentInsetBottom != lastDialogContentInsetBottom) else {
      return
    }

    lastSafeAreaInsets = safeAreaInsets
    lastColorScheme = colorScheme
    lastLocale = locale
    lastDialogContentInsetBottom = contentInsetBottom
    let updateMeta = LynxUpdateMeta()
    updateMeta.data = nativeEnvironmentData(safeAreaInsets)
    lynxView?.updateMetaData(updateMeta)
  }

  private func nativeEnvironmentData(_ insets: UIEdgeInsets) -> LynxTemplateData {
    var additionalData: [String: Any] = [
      "nativeEnvironment": [
        "colorScheme": nativeColorScheme,
        "locale": nativeLocale,
      ],
    ]
    if var route {
      if isInputDialogRoute {
        route["contentInsetBottom"] = dialogContentInsetBottom
      }
      additionalData["route"] = route
    }
    return LynxDeviceTemplateData(insets, additionalData)
  }

  private var nativeColorScheme: String {
    traitCollection.userInterfaceStyle == .dark ? "dark" : "light"
  }

  private var nativeLocale: String {
    Bundle.main.preferredLocalizations.first
      ?? Locale.preferredLanguages.first
      ?? Locale.current.identifier
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
