import UIKit

/// Liquid Glass custom Lynx elements (iOS 26+, graceful degradation below).
///
/// Two native elements are registered for the Lynx engine:
/// - `glass-switch`: wraps UISwitch, which renders with the Liquid Glass
///   appearance on iOS 26.
/// - `glass-dropdown`: wraps a UIButton with UIButton.Configuration.glass()
///   and a UIMenu, giving a Liquid Glass pull-down menu.
///
/// Props are exposed to the Lynx props processor through class methods named
/// `__lynx_prop_config__*`, mirroring what the ObjC LYNX_PROP_SETTER macro
/// generates. Each config entry maps a prop name to an instance setter with
/// selector `<setter>:requestReset:` and a LynxConverter type name.
///
/// Events are emitted as LynxDetailEvent, so front-end handlers read
/// `event.detail`.

@objcMembers
final class LynxUIGlassSwitch: LynxUI<UISwitch> {

  // MARK: Prop config (consumed by LynxPropsProcessor)

  @objc(__lynx_prop_config__checked)
  class func propConfigChecked() -> [String] {
    ["checked", "setChecked", "BOOL"]
  }

  @objc(__lynx_prop_config__disabled)
  class func propConfigDisabled() -> [String] {
    ["disabled", "setDisabled", "BOOL"]
  }

  // MARK: LynxUI

  override func createView() -> UISwitch? {
    let toggle = UISwitch()
    toggle.addTarget(
      self,
      action: #selector(handleValueChanged(_:)),
      for: .valueChanged
    )
    return toggle
  }

  // MARK: Prop setters

  func setChecked(_ value: Bool, requestReset: Bool) {
    view().setOn(!requestReset && value, animated: true)
  }

  func setDisabled(_ value: Bool, requestReset: Bool) {
    view().isEnabled = requestReset ? true : !value
  }

  // MARK: Events

  @objc private func handleValueChanged(_ sender: UISwitch) {
    emitDetailEvent(from: self, name: "change", detail: ["value": sender.isOn])
  }
}

@objcMembers
final class LynxUIGlassDropdown: LynxUI<UIButton> {

  private var title: String = ""
  private var options: [String] = []
  private var selected: Int = -1
  private var disabled = false

  // MARK: Prop config (consumed by LynxPropsProcessor)

  @objc(__lynx_prop_config__title)
  class func propConfigTitle() -> [String] {
    ["title", "setTitle", "NSString*"]
  }

  @objc(__lynx_prop_config__options)
  class func propConfigOptions() -> [String] {
    ["options", "setOptions", "NSArray*"]
  }

  @objc(__lynx_prop_config__selected)
  class func propConfigSelected() -> [String] {
    ["selected", "setSelected", "NSInteger"]
  }

  @objc(__lynx_prop_config__disabled)
  class func propConfigDisabled() -> [String] {
    ["disabled", "setDisabled", "BOOL"]
  }

  // MARK: LynxUI

  override func createView() -> UIButton? {
    let button: UIButton
    if #available(iOS 26.0, *) {
      button = UIButton(configuration: .glass())
    } else if #available(iOS 15.0, *) {
      var fallback = UIButton.Configuration.filled()
      fallback.baseBackgroundColor = .systemBlue
      fallback.cornerStyle = .capsule
      button = UIButton(configuration: fallback)
    } else {
      button = UIButton(type: .system)
    }
    if #available(iOS 14.0, *) {
      button.showsMenuAsPrimaryAction = true
    }
    if #available(iOS 15.0, *) {
      button.changesSelectionAsPrimaryAction = false
      button.configuration?.contentInsets = NSDirectionalEdgeInsets(
        top: 0, leading: 16, bottom: 0, trailing: 16
      )
    } else {
      button.contentEdgeInsets = UIEdgeInsets(
        top: 0, left: 16, bottom: 0, right: 16
      )
      button.addTarget(
        self,
        action: #selector(handleLegacyTap),
        for: .touchUpInside
      )
    }
    button.contentHorizontalAlignment = .leading
    return button
  }

  // MARK: Prop setters

  func setTitle(_ value: NSString?, requestReset: Bool) {
    title = requestReset ? "" : (value as String? ?? "")
    applyContent()
  }

  func setOptions(_ value: NSArray?, requestReset: Bool) {
    options = requestReset ? [] : (value as? [String] ?? [])
    if selected >= options.count { selected = -1 }
    applyContent()
  }

  func setSelected(_ value: Int, requestReset: Bool) {
    selected = requestReset ? -1 : value
    applyContent()
  }

  func setDisabled(_ value: Bool, requestReset: Bool) {
    disabled = requestReset ? false : value
    view().isEnabled = !disabled
  }

  // MARK: Rendering

  private func applyContent() {
    let label = selected >= 0 && selected < options.count
      ? options[selected]
      : (title.isEmpty ? "Select…" : title)
    let button = view()
    if #available(iOS 15.0, *) {
      button.configuration?.title = label
      button.configuration?.image = UIImage(
        systemName: "chevron.up.chevron.down"
      )
      button.configuration?.imagePlacement = .trailing
      button.configuration?.imagePadding = 8
    } else {
      button.setTitle(label, for: .normal)
    }
    rebuildMenu()
  }

  private func rebuildMenu() {
    guard #available(iOS 14.0, *) else { return }
    let actions: [UIAction] = options.enumerated().map { index, option in
      let action = UIAction(title: option) { [weak self] _ in
        guard let self else { return }
        self.selected = index
        self.applyContent()
        emitDetailEvent(
          from: self,
          name: "select",
          detail: ["index": index, "value": option]
        )
      }
      action.state = index == selected ? .on : .off
      return action
    }
    if #available(iOS 15.0, *) {
      view().menu = UIMenu(options: .singleSelection, children: actions)
    } else {
      view().menu = UIMenu(children: actions)
    }
  }

  /// iOS 13 fallback: cycle through options on tap (no UIMenu available).
  @objc private func handleLegacyTap() {
    guard !options.isEmpty else { return }
    selected = (selected + 1) % options.count
    applyContent()
    emitDetailEvent(
      from: self,
      name: "select",
      detail: ["index": selected, "value": options[selected]]
    )
  }
}

// MARK: - Shared event helper

/// Extensions of generic ObjC classes cannot touch generic params in Swift,
/// so event emission lives in a free function instead of a LynxUI extension.
private func emitDetailEvent<V: UIView>(
  from ui: LynxUI<V>,
  name: String,
  detail: [String: Any]
) {
  guard let context = ui.context else { return }
  let event = LynxDetailEvent(name: name, targetSign: ui.sign, detail: detail)
  context.eventEmitter?.dispatchCustomEvent(event)
}

// MARK: - Registration

enum LiquidGlassElements {
  /// Must run before any LynxView is created.
  static func register() {
    LynxComponentRegistry.registerUI(
      LynxUIGlassSwitch.self,
      withName: "glass-switch"
    )
    LynxComponentRegistry.registerUI(
      LynxUIGlassDropdown.self,
      withName: "glass-dropdown"
    )
  }
}
