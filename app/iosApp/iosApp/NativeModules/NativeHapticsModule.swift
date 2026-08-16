import UIKit

@objcMembers
final class NativeHapticsModule: NSObject, LynxModule {
  static let name = "NativeHapticsModule"
  static let methodLookup = [
    "impact": "impact:callback:",
  ]

  override init() {
    super.init()
  }

  @objc(initWithParam:)
  init(param: Any) {
    super.init()
  }

  func impact(_ style: String, callback: LynxCallbackBlock) {
    let feedbackStyle: UIImpactFeedbackGenerator.FeedbackStyle
    switch style {
    case "light":
      feedbackStyle = .light
    case "medium":
      feedbackStyle = .medium
    case "heavy":
      feedbackStyle = .heavy
    default:
      callback("Invalid haptic impact style: \(style)")
      return
    }
    let generator = UIImpactFeedbackGenerator(style: feedbackStyle)
    generator.prepare()
    generator.impactOccurred()
    callback("")
  }
}
