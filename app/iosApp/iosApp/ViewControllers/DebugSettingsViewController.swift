#if DEBUG
import UIKit

/// Native settings screen compiled only into the iOS Debug configuration.
final class DebugSettingsViewController: UIViewController {
  var onSettingsChanged: (() -> Void)?

  private let bundleServerStack = UIStackView()
  private var bundleServers: [BundleServer] = []

  override func viewDidLoad() {
    super.viewDidLoad()
    title = "Lynx development"
    view.backgroundColor = Self.pageBackground
    navigationItem.rightBarButtonItem = UIBarButtonItem(
      barButtonSystemItem: .close,
      target: self,
      action: #selector(close)
    )
    buildForm()
    populate(DevelopmentSettings.snapshot)
  }

  private func buildForm() {
    let scrollView = UIScrollView()
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(scrollView)

    let stack = UIStackView()
    stack.axis = .vertical
    stack.spacing = 10
    stack.translatesAutoresizingMaskIntoConstraints = false
    scrollView.addSubview(stack)

    stack.addArrangedSubview(bodyLabel(
      "Debug only · saved on this device. Release builds neither expose nor read these values."
    ))
    stack.setCustomSpacing(24, after: stack.arrangedSubviews.last!)

    stack.addArrangedSubview(sectionLabel("Bundle servers"))
    stack.addArrangedSubview(bodyLabel(
      "Choose a bundle loaded on this device or enter an ID manually. A server root resolves to /<id>.lynx.bundle; a full bundle URL is used unchanged."
    ))

    bundleServerStack.axis = .vertical
    bundleServerStack.spacing = 8
    stack.addArrangedSubview(bundleServerStack)

    let addButton = actionButton(
      title: "Add bundle server",
      action: #selector(addBundleServer)
    )
    stack.addArrangedSubview(addButton)
    stack.setCustomSpacing(24, after: addButton)

    let saveButton = actionButton(
      title: "Save & reload",
      action: #selector(save)
    )
    stack.addArrangedSubview(saveButton)
    let clearButton = actionButton(
      title: "Clear overrides & reload",
      action: #selector(clear),
      backgroundColor: UIColor(
        red: 52 / 255,
        green: 66 / 255,
        blue: 62 / 255,
        alpha: 1
      )
    )
    stack.addArrangedSubview(clearButton)

    NSLayoutConstraint.activate([
      scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
      scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 24),
      stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -24),
      stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 20),
      stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
      stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -48),
      addButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 46),
      saveButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 46),
      clearButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 46),
    ])
  }

  private func populate(_ snapshot: DevelopmentSettingsSnapshot) {
    bundleServers = snapshot.bundleServers
    renderBundleServers()
  }

  private func renderBundleServers() {
    bundleServerStack.arrangedSubviews.forEach { child in
      bundleServerStack.removeArrangedSubview(child)
      child.removeFromSuperview()
    }

    guard !bundleServers.isEmpty else {
      let empty = bodyLabel("No bundle servers configured.")
      let wrapper = UIStackView(arrangedSubviews: [empty])
      wrapper.backgroundColor = Self.cardBackground
      wrapper.layer.cornerRadius = 8
      wrapper.isLayoutMarginsRelativeArrangement = true
      wrapper.directionalLayoutMargins = NSDirectionalEdgeInsets(
        top: 14,
        leading: 14,
        bottom: 14,
        trailing: 14
      )
      bundleServerStack.addArrangedSubview(wrapper)
      return
    }

    for (index, mapping) in bundleServers.enumerated() {
      bundleServerStack.addArrangedSubview(
        bundleServerRow(mapping: mapping, index: index)
      )
    }
  }

  private func bundleServerRow(mapping: BundleServer, index: Int) -> UIView {
    let bundleLabel = UILabel()
    bundleLabel.text = mapping.bundleID
    bundleLabel.textColor = .white
    bundleLabel.font = .preferredFont(forTextStyle: .headline)

    let serverLabel = bodyLabel(mapping.server)
    serverLabel.lineBreakMode = .byCharWrapping

    let editButton = secondaryButton(
      title: "Edit",
      color: .systemBlue,
      action: #selector(editBundleServer(_:)),
      tag: index
    )
    let deleteButton = secondaryButton(
      title: "Delete",
      color: .systemRed,
      action: #selector(deleteBundleServer(_:)),
      tag: index
    )
    let actions = UIStackView(arrangedSubviews: [editButton, deleteButton])
    actions.axis = .horizontal
    actions.distribution = .fillEqually
    actions.spacing = 8

    let content = UIStackView(arrangedSubviews: [
      bundleLabel,
      serverLabel,
      actions,
    ])
    content.axis = .vertical
    content.spacing = 6
    content.isLayoutMarginsRelativeArrangement = true
    content.directionalLayoutMargins = NSDirectionalEdgeInsets(
      top: 12,
      leading: 14,
      bottom: 10,
      trailing: 14
    )
    content.backgroundColor = Self.cardBackground
    content.layer.cornerRadius = 8
    editButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 38).isActive = true
    return content
  }

  @objc private func addBundleServer() {
    openEditor(editingIndex: nil)
  }

  @objc private func editBundleServer(_ sender: UIButton) {
    guard bundleServers.indices.contains(sender.tag) else { return }
    openEditor(editingIndex: sender.tag)
  }

  @objc private func deleteBundleServer(_ sender: UIButton) {
    guard bundleServers.indices.contains(sender.tag) else { return }
    bundleServers.remove(at: sender.tag)
    renderBundleServers()
  }

  private func openEditor(editingIndex: Int?) {
    let existing = editingIndex.flatMap { index in
      bundleServers.indices.contains(index) ? bundleServers[index] : nil
    }
    var unavailableBundleIDs = Set(bundleServers.map(\.bundleID))
    if let existing { unavailableBundleIDs.remove(existing.bundleID) }

    let editor = BundleServerEditorViewController(
      mapping: existing,
      loadedBundleIDs: DevelopmentSettings.loadedBundleIDs,
      unavailableBundleIDs: unavailableBundleIDs
    )
    editor.onSave = { [weak self] mapping in
      guard let self else { return }
      if let editingIndex,
         bundleServers.indices.contains(editingIndex) {
        bundleServers[editingIndex] = mapping
      } else {
        bundleServers.append(mapping)
      }
      renderBundleServers()
      navigationController?.popToViewController(self, animated: true)
    }
    navigationController?.pushViewController(editor, animated: true)
  }

  @objc private func save() {
    do {
      populate(try DevelopmentSettings.save(bundleServers: bundleServers))
      finishWithReload()
    } catch {
      show(error.localizedDescription, title: "Invalid settings")
    }
  }

  @objc private func clear() {
    DevelopmentSettings.clear()
    populate(DevelopmentSettings.snapshot)
    finishWithReload()
  }

  @objc private func close() {
    dismiss(animated: true)
  }

  private func finishWithReload() {
    onSettingsChanged?()
    dismiss(animated: true)
  }

  private func show(_ message: String, title: String) {
    let alert = UIAlertController(
      title: title,
      message: message,
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "OK", style: .default))
    present(alert, animated: true)
  }

  private func sectionLabel(_ text: String) -> UILabel {
    let label = UILabel()
    label.text = text
    label.textColor = .white
    label.font = .preferredFont(forTextStyle: .headline)
    return label
  }

  private func bodyLabel(_ text: String) -> UILabel {
    let label = UILabel()
    label.text = text
    label.textColor = UIColor(
      red: 155 / 255,
      green: 176 / 255,
      blue: 170 / 255,
      alpha: 1
    )
    label.font = .preferredFont(forTextStyle: .footnote)
    label.numberOfLines = 0
    return label
  }

  private func actionButton(
    title: String,
    action: Selector,
    backgroundColor: UIColor = UIColor(
      red: 43 / 255,
      green: 99 / 255,
      blue: 241 / 255,
      alpha: 1
    )
  ) -> UIButton {
    let button = UIButton(type: .system)
    button.setTitle(title, for: .normal)
    button.titleLabel?.font = .preferredFont(forTextStyle: .headline)
    button.backgroundColor = backgroundColor
    button.setTitleColor(.white, for: .normal)
    button.layer.cornerRadius = 10
    button.addTarget(self, action: action, for: .touchUpInside)
    return button
  }

  private func secondaryButton(
    title: String,
    color: UIColor,
    action: Selector,
    tag: Int
  ) -> UIButton {
    let button = UIButton(type: .system)
    button.setTitle(title, for: .normal)
    button.setTitleColor(color, for: .normal)
    button.backgroundColor = UIColor.white.withAlphaComponent(0.06)
    button.layer.cornerRadius = 8
    button.tag = tag
    button.addTarget(self, action: action, for: .touchUpInside)
    return button
  }

  private static let pageBackground = UIColor(
    red: 7 / 255,
    green: 16 / 255,
    blue: 15 / 255,
    alpha: 1
  )
  private static let cardBackground = UIColor(
    red: 19 / 255,
    green: 33 / 255,
    blue: 30 / 255,
    alpha: 1
  )
}

/// Add/edit form with a native pull-down menu and a manual bundle-ID fallback.
private final class BundleServerEditorViewController: UIViewController {
  var onSave: ((BundleServer) -> Void)?

  private let mapping: BundleServer?
  private let loadedBundleIDs: [String]
  private let unavailableBundleIDs: Set<String>
  private let loadedBundleButton = UIButton(type: .system)
  private let bundleIDField = UITextField()
  private let serverField = UITextField()

  init(
    mapping: BundleServer?,
    loadedBundleIDs: [String],
    unavailableBundleIDs: Set<String>
  ) {
    self.mapping = mapping
    self.loadedBundleIDs = loadedBundleIDs
    self.unavailableBundleIDs = unavailableBundleIDs
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    title = mapping == nil ? "Add bundle server" : "Edit bundle server"
    view.backgroundColor = UIColor(
      red: 7 / 255,
      green: 16 / 255,
      blue: 15 / 255,
      alpha: 1
    )
    navigationItem.rightBarButtonItem = UIBarButtonItem(
      barButtonSystemItem: .save,
      target: self,
      action: #selector(save)
    )
    buildForm()
    populate()
  }

  private func buildForm() {
    let scrollView = UIScrollView()
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(scrollView)

    let stack = UIStackView()
    stack.axis = .vertical
    stack.spacing = 8
    stack.translatesAutoresizingMaskIntoConstraints = false
    scrollView.addSubview(stack)

    stack.addArrangedSubview(fieldLabel("Loaded bundle"))
    loadedBundleButton.contentHorizontalAlignment = .left
    loadedBundleButton.setTitleColor(.white, for: .normal)
    loadedBundleButton.backgroundColor = UIColor(
      red: 19 / 255,
      green: 33 / 255,
      blue: 30 / 255,
      alpha: 1
    )
    loadedBundleButton.layer.cornerRadius = 8
    loadedBundleButton.contentEdgeInsets = UIEdgeInsets(
      top: 12,
      left: 14,
      bottom: 12,
      right: 14
    )
    configureLoadedBundleMenu()
    stack.addArrangedSubview(loadedBundleButton)
    stack.setCustomSpacing(18, after: loadedBundleButton)

    stack.addArrangedSubview(fieldLabel("Bundle ID (or enter manually)"))
    configureTextField(bundleIDField, placeholder: "native-capabilities")
    bundleIDField.autocapitalizationType = .none
    bundleIDField.autocorrectionType = .no
    stack.addArrangedSubview(bundleIDField)
    stack.setCustomSpacing(18, after: bundleIDField)

    stack.addArrangedSubview(fieldLabel("Server URL"))
    configureTextField(serverField, placeholder: "http://192.168.1.10:3000")
    serverField.keyboardType = .URL
    serverField.autocapitalizationType = .none
    serverField.autocorrectionType = .no
    stack.addArrangedSubview(serverField)

    let help = UILabel()
    help.text = "A server root appends /<id>.lynx.bundle. You can also enter a complete .lynx.bundle URL."
    help.textColor = UIColor(
      red: 155 / 255,
      green: 176 / 255,
      blue: 170 / 255,
      alpha: 1
    )
    help.font = .preferredFont(forTextStyle: .footnote)
    help.numberOfLines = 0
    stack.addArrangedSubview(help)

    NSLayoutConstraint.activate([
      scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
      scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 24),
      stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -24),
      stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 20),
      stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
      stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -48),
      bundleIDField.heightAnchor.constraint(greaterThanOrEqualToConstant: 46),
      serverField.heightAnchor.constraint(greaterThanOrEqualToConstant: 46),
    ])
  }

  private func populate() {
    bundleIDField.text = mapping?.bundleID
    serverField.text = mapping?.server
    if let bundleID = mapping?.bundleID,
       loadedBundleIDs.contains(bundleID) {
      loadedBundleButton.setTitle("\(bundleID)  ▾", for: .normal)
    }
  }

  private func configureLoadedBundleMenu() {
    guard !loadedBundleIDs.isEmpty else {
      loadedBundleButton.setTitle("No loaded bundles yet", for: .normal)
      loadedBundleButton.isEnabled = false
      loadedBundleButton.alpha = 0.55
      return
    }
    loadedBundleButton.setTitle("Choose a loaded bundle  ▾", for: .normal)
    if #available(iOS 14.0, *) {
      loadedBundleButton.menu = UIMenu(
        title: "Loaded bundles",
        children: loadedBundleIDs.map { bundleID in
          UIAction(title: bundleID) { [weak self] _ in
            self?.selectLoadedBundle(bundleID)
          }
        }
      )
      loadedBundleButton.showsMenuAsPrimaryAction = true
    } else {
      loadedBundleButton.addTarget(
        self,
        action: #selector(showLegacyBundleMenu),
        for: .touchUpInside
      )
    }
  }

  private func selectLoadedBundle(_ bundleID: String) {
    bundleIDField.text = bundleID
    loadedBundleButton.setTitle("\(bundleID)  ▾", for: .normal)
  }

  @objc private func showLegacyBundleMenu() {
    let alert = UIAlertController(
      title: "Loaded bundles",
      message: nil,
      preferredStyle: .actionSheet
    )
    loadedBundleIDs.forEach { bundleID in
      alert.addAction(UIAlertAction(title: bundleID, style: .default) {
        [weak self] _ in self?.selectLoadedBundle(bundleID)
      })
    }
    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    if let popover = alert.popoverPresentationController {
      popover.sourceView = loadedBundleButton
      popover.sourceRect = loadedBundleButton.bounds
    }
    present(alert, animated: true)
  }

  @objc private func save() {
    do {
      let normalized = try DevelopmentSettings.validatedBundleServer(
        bundleID: bundleIDField.text ?? "",
        server: serverField.text ?? ""
      )
      guard !unavailableBundleIDs.contains(normalized.bundleID) else {
        show("A server is already configured for \(normalized.bundleID).")
        return
      }
      onSave?(normalized)
    } catch {
      show(error.localizedDescription)
    }
  }

  private func show(_ message: String) {
    let alert = UIAlertController(
      title: "Invalid bundle server",
      message: message,
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "OK", style: .default))
    present(alert, animated: true)
  }

  private func fieldLabel(_ text: String) -> UILabel {
    let label = UILabel()
    label.text = text
    label.textColor = .white
    label.font = .preferredFont(forTextStyle: .headline)
    return label
  }

  private func configureTextField(_ field: UITextField, placeholder: String) {
    field.placeholder = placeholder
    field.textColor = .white
    field.backgroundColor = UIColor(
      red: 19 / 255,
      green: 33 / 255,
      blue: 30 / 255,
      alpha: 1
    )
    field.layer.cornerRadius = 8
    field.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 14, height: 1))
    field.leftViewMode = .always
    field.rightView = UIView(frame: CGRect(x: 0, y: 0, width: 14, height: 1))
    field.rightViewMode = .always
  }
}
#endif
