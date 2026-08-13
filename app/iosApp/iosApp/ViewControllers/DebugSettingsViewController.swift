#if DEBUG
import UIKit

/// Native settings screen compiled only into the iOS Debug configuration.
final class DebugSettingsViewController: UIViewController {
  var onSettingsChanged: (() -> Void)?

  private let apiServerField = UITextField()
  private let bundleServersField = UITextView()

  override func viewDidLoad() {
    super.viewDidLoad()
    title = "Lynx development"
    view.backgroundColor = UIColor(
      red: 7 / 255,
      green: 16 / 255,
      blue: 15 / 255,
      alpha: 1
    )
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

    stack.addArrangedSubview(sectionLabel("API Server"))
    apiServerField.borderStyle = .roundedRect
    apiServerField.placeholder = "http://192.168.1.10:8080"
    apiServerField.keyboardType = .URL
    apiServerField.autocapitalizationType = .none
    apiServerField.autocorrectionType = .no
    stack.addArrangedSubview(apiServerField)
    stack.addArrangedSubview(bodyLabel(
      "Injected into every bundle as nativeEnvironment.apiServer."
    ))
    stack.setCustomSpacing(24, after: stack.arrangedSubviews.last!)

    stack.addArrangedSubview(sectionLabel("Bundle servers"))
    bundleServersField.backgroundColor = UIColor(
      red: 19 / 255,
      green: 33 / 255,
      blue: 30 / 255,
      alpha: 1
    )
    bundleServersField.textColor = .white
    bundleServersField.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
    bundleServersField.autocapitalizationType = .none
    bundleServersField.autocorrectionType = .no
    bundleServersField.layer.cornerRadius = 8
    bundleServersField.layer.borderWidth = 1
    bundleServersField.layer.borderColor = UIColor.white.withAlphaComponent(0.12).cgColor
    bundleServersField.heightAnchor.constraint(equalToConstant: 170).isActive = true
    stack.addArrangedSubview(bundleServersField)
    stack.addArrangedSubview(bodyLabel(
      "One bundle-id=URL per line. A server root becomes /<id>.lynx.bundle; a full .lynx.bundle URL is used unchanged."
    ))
    stack.setCustomSpacing(24, after: stack.arrangedSubviews.last!)

    let saveButton = actionButton(title: "Save & reload", action: #selector(save))
    stack.addArrangedSubview(saveButton)
    let clearButton = actionButton(
      title: "Clear overrides & reload",
      action: #selector(clear)
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
      saveButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 46),
      clearButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 46),
    ])
  }

  private func populate(_ snapshot: DevelopmentSettingsSnapshot) {
    apiServerField.text = snapshot.apiServer
    bundleServersField.text = snapshot.bundleServers
  }

  @objc private func save() {
    do {
      let snapshot = try DevelopmentSettings.save(
        apiServer: apiServerField.text ?? "",
        bundleServers: bundleServersField.text
      )
      populate(snapshot)
      finishWithReload()
    } catch {
      show(error.localizedDescription)
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

  private func show(_ message: String) {
    let alert = UIAlertController(
      title: "Invalid settings",
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

  private func actionButton(title: String, action: Selector) -> UIButton {
    let button = UIButton(type: .system)
    button.setTitle(title, for: .normal)
    button.titleLabel?.font = .preferredFont(forTextStyle: .headline)
    button.backgroundColor = UIColor(
      red: 43 / 255,
      green: 99 / 255,
      blue: 241 / 255,
      alpha: 1
    )
    button.setTitleColor(.white, for: .normal)
    button.layer.cornerRadius = 10
    button.addTarget(self, action: action, for: .touchUpInside)
    return button
  }
}
#endif
