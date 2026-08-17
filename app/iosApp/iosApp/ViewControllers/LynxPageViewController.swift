import UIKit

/// Reusable native host for both the storyboard root and routed Lynx bundles.
class LynxPageViewController: UIViewController {
  private let bundleRepository = LynxBundleRepository()
  private let bundleName: String
  private let route: [String: Any]?
  private let transparent: Bool

  var routeAnimation: NativeRouteAnimation {
    NativeRouteAnimation(rawValue: route?["animation"] as? String ?? "") ?? .standard
  }
  private var nativeStatusBarStyle: NativeStatusBarStyle
  private var lynxView: LynxView?
  private var nativeBackController: NativeBackController?
  private var hasLoadedInitialBundle = false
  private var canUpdateTemplate = false
  private var lastSafeAreaInsets: UIEdgeInsets?

  init(
    bundleName: String,
    route: [String: Any],
    transparent: Bool,
    statusBarStyle: NativeStatusBarStyle
  ) {
    self.bundleName = bundleName
    self.route = route
    self.transparent = transparent
    nativeStatusBarStyle = statusBarStyle
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    bundleName = "main"
    route = nil
    transparent = false
    nativeStatusBarStyle = .darkContent
    super.init(coder: coder)
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = transparent
      ? .clear
      : UIColor(red: 247 / 255, green: 247 / 255, blue: 251 / 255, alpha: 1)

    // The explicit host adapter records the exact module registry installed
    // on this view; the autolinked native component owns only WebView/RPC.
    let config = WebviewModuleBridgeHostAdapter.makeConfig(
      provider: bundleRepository
    )
    let nativeBackController = NativeBackController(host: self)
    config.register(StatusBarModule.self, param: self)
    config.register(BackModule.self, param: nativeBackController)
    // Router, WebSocket, MMKV storage, clipboard and haptics come from the
    // autolink/* workspace libraries; HarmonyOS hosts register their own
    // instead. The Router's host navigation installs once in AppDelegate.
    LynxGeneratedLibraryRegistry().setup(config)
    let lynxView = LynxView { builder in
      builder.config = config
      builder.genericResourceFetcher = AppGenericResourceFetcher()
      builder.enableGenericResourceFetcher = .true
      builder.screenSize = self.view.frame.size
      builder.fontScale = 1.0
    }
    WebviewModuleBridgeHostAdapter.attach(config, to: lynxView)

    lynxView.backgroundColor = transparent ? .clear : view.backgroundColor
    lynxView.isOpaque = !transparent
    lynxView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    lynxView.frame = view.bounds
    lynxView.preferredLayoutWidth = self.view.frame.size.width
    lynxView.preferredLayoutHeight = self.view.frame.size.height
    lynxView.layoutWidthMode = .exact
    lynxView.layoutHeightMode = .exact
    view.addSubview(lynxView)
    self.lynxView = lynxView
    self.nativeBackController = nativeBackController
    nativeBackController.attach(lynxView: lynxView)

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
    lynxView?.frame = view.bounds
    lynxView?.preferredLayoutWidth = view.bounds.width
    lynxView?.preferredLayoutHeight = view.bounds.height
    loadInitialBundleIfReady()
    updateNativeEnvironmentIfNeeded()
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    nativeBackController?.setVisible(true)
    loadInitialBundleIfReady()
  }

  override var preferredStatusBarStyle: UIStatusBarStyle {
    nativeStatusBarStyle.uiStyle
  }

  func setNativeStatusBarStyle(_ style: NativeStatusBarStyle) {
    nativeStatusBarStyle = style
    setNeedsStatusBarAppearanceUpdate()
  }

  override func viewWillDisappear(_ animated: Bool) {
    nativeBackController?.setVisible(false)
    super.viewWillDisappear(animated)
  }

  deinit {
    nativeBackController?.destroy()
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
    var data: [String: Any] = [
      "nativeEnvironment": [
        "schemaVersion": 1,
        "unit": "px",
        "safeAreaInsets": [
          "top": Double(insets.top),
          "right": Double(insets.right),
          "bottom": Double(insets.bottom),
          "left": Double(insets.left),
        ],
      ],
    ]
    if let route {
      data["route"] = route
    }
    return LynxTemplateData(dictionary: data)
  }

  private func sameInsets(_ lhs: UIEdgeInsets, _ rhs: UIEdgeInsets?) -> Bool {
    guard let rhs else { return false }
    return lhs.top == rhs.top
      && lhs.right == rhs.right
      && lhs.bottom == rhs.bottom
      && lhs.left == rhs.left
  }

  #if DEBUG
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
    view.addSubview(button)
    NSLayoutConstraint.activate([
      button.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
      button.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
      button.widthAnchor.constraint(equalToConstant: 54),
      button.heightAnchor.constraint(equalToConstant: 34),
    ])
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
