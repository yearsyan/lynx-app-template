import UIKit

/// Code-only entry point. The scene delegate mounts this controller as the
/// window's root view controller; routed pages instantiate LynxPageViewController directly.
final class ViewController: LynxPageViewController {
  init() {
    // Same defaults as the former storyboard path: "main" bundle, no route.
    super.init(bundleName: "main", route: nil, snapshot: nil, statusBarStyle: .darkContent)
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
  }
}
