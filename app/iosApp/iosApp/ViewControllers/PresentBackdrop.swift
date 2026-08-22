import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

extension UIColor {
  /// Parses '#AARRGGBB' (alpha first), the shared route scrim color format.
  convenience init?(lynxHexARGB: String) {
    var hex = lynxHexARGB
    guard hex.hasPrefix("#") else { return nil }
    hex.removeFirst()
    guard hex.count == 8, let value = UInt32(hex, radix: 16) else { return nil }
    self.init(
      red: CGFloat((value >> 16) & 0xFF) / 255,
      green: CGFloat((value >> 8) & 0xFF) / 255,
      blue: CGFloat(value & 0xFF) / 255,
      alpha: CGFloat((value >> 24) & 0xFF) / 255
    )
  }
}

/// Per-phase content choreography shared by the route handler and backdrop.
struct PresentContentAnimationOptions {
  let opacity: Bool
  let push: Bool

  var isEnabled: Bool { opacity || push }

  static let standard = PresentContentAnimationOptions(opacity: false, push: true)
}

/// Simulates an iOS-style present transition for an opaque Lynx page. The
/// previous page's snapshot fills the new view from viewDidLoad (before the
/// first frame), so pushing with no animation is imperceptible; when the Lynx
/// content paints its first screen the backdrop shrinks with rounded corners
/// while the content slides in. Dismissing reverses both before the page
/// really pops, so the revealed previous page stays pixel-aligned with the
/// restored snapshot.
///
/// The backdrop and content choreographies can be cleared independently, and a
/// blurred backdrop is captured at reduced resolution (no pixel alignment is
/// attempted) with a gaussian pass applied to the image.
final class PresentBackdrop {
  private static let duration: TimeInterval = 0.35
  private static let backdropShift: CGFloat = 0.08
  /// Fallback for systems before UIKit gained container-concentric corners.
  private static let legacyCornerRadius: CGFloat = 12
  /// Blurred snapshots are rendered at this scale and softened by this radius.
  private static let blurredCaptureScale: CGFloat = 1 / 3
  private static let blurRadius: Float = 12
  /// Default scrim: 35% black ('#59000000').
  static let defaultScrimColor = UIColor(white: 0, alpha: 0.35)

  /// Fullscreen snapshot layer that sits behind the transparent LynxView.
  let view: UIImageView
  /// Stationary dim layer between the snapshot and the content. The color
  /// carries the dimming alpha; the choreography only fades the layer itself
  /// in place. When neither transition plays the scrim is static from the
  /// first frame.
  let scrim = UIView()
  private let playsBackdropTransition: Bool
  private let enterAnimation: PresentContentAnimationOptions
  private let exitAnimation: PresentContentAnimationOptions
  private var playsPresentChoreography: Bool {
    playsBackdropTransition || enterAnimation.isEnabled
  }
  private var playsDismissChoreography: Bool {
    playsBackdropTransition || exitAnimation.isEnabled
  }
  private var presented = false
  private var preservedCornerRadii: (topLeft: CGFloat, topRight: CGFloat)?
  private var interactiveDismissFraction: CGFloat?
  private var interactiveDismissReady = false

  var canBeginInteractiveDismiss: Bool {
    presented && interactiveDismissReady && playsDismissChoreography
  }

  init(
    image: UIImage,
    scrimColor: UIColor = PresentBackdrop.defaultScrimColor,
    playsBackdropTransition: Bool = true,
    enterAnimation: PresentContentAnimationOptions = .standard,
    exitAnimation: PresentContentAnimationOptions = .standard
  ) {
    self.playsBackdropTransition = playsBackdropTransition
    self.enterAnimation = enterAnimation
    self.exitAnimation = exitAnimation
    view = UIImageView(image: image)
    view.contentMode = .scaleToFill
    restoreCornerClipping()
    scrim.backgroundColor = scrimColor
    scrim.alpha = playsPresentChoreography ? 0 : 1
  }

  /// Saves the exact screen-concentric radii while this page is still in its
  /// original navigation container. UIKit can no longer derive those values
  /// after a nested route temporarily reparents the page for its transition.
  func preserveCornerClipping() {
    if #available(iOS 26.0, *) {
      let topLeft = view.effectiveRadius(corner: .topLeft)
      let topRight = view.effectiveRadius(corner: .topRight)
      guard topLeft > 0, topRight > 0 else { return }
      preservedCornerRadii = (topLeft: topLeft, topRight: topRight)
    }
  }

  /// Reinstalls the snapshot's clipping after a nested navigation transition.
  /// On iOS 26, a container-concentric radius is derived from the view's
  /// current container geometry. UINavigationController temporarily moves the
  /// underlying page through its transition container while popping a nested
  /// route, which can leave that dynamic radius resolved as square even though
  /// the snapshot transform is preserved.
  func restoreCornerClipping() {
    view.clipsToBounds = true
    if #available(iOS 26.0, *) {
      let topLeftRadius: UICornerRadius
      let topRightRadius: UICornerRadius
      if let preservedCornerRadii {
        topLeftRadius = .fixed(Double(preservedCornerRadii.topLeft))
        topRightRadius = .fixed(Double(preservedCornerRadii.topRight))
      } else {
        topLeftRadius = .containerConcentric()
        topRightRadius = .containerConcentric()
      }
      view.cornerConfiguration = .corners(
        topLeftRadius: topLeftRadius,
        topRightRadius: topRightRadius,
        bottomLeftRadius: nil,
        bottomRightRadius: nil
      )
    } else {
      view.layer.cornerCurve = .continuous
      view.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
      if presented {
        view.layer.cornerRadius = Self.legacyCornerRadius
      }
    }
  }

  /// Captures the current pixels of `source`; the layer fallback covers views
  /// that are not composited on screen yet. Blurred captures render at reduced
  /// size and get a gaussian pass, so they stay cheap and need no alignment.
  static func capture(of source: UIView, blurred: Bool = false) -> UIImage? {
    guard source.bounds.width > 0, source.bounds.height > 0 else {
      return nil
    }
    let scale: CGFloat = blurred ? blurredCaptureScale : 1
    let size = CGSize(
      width: source.bounds.width * scale,
      height: source.bounds.height * scale
    )
    let renderer = UIGraphicsImageRenderer(size: size)
    let image = renderer.image { context in
      // afterScreenUpdates:false keeps the current pixels instead of forcing
      // an offscreen update pass first.
      let drew = source.drawHierarchy(
        in: CGRect(origin: .zero, size: size),
        afterScreenUpdates: false
      )
      if !drew {
        context.cgContext.concatenate(CGAffineTransform(scaleX: scale, y: scale))
        source.layer.render(in: context.cgContext)
      }
    }
    return blurred ? gaussianBlurred(image) : image
  }

  private static func gaussianBlurred(_ image: UIImage) -> UIImage {
    guard let cgImage = image.cgImage else { return image }
    let input = CIImage(cgImage: cgImage)
    let filter = CIFilter.gaussianBlur()
    filter.inputImage = input.clampedToExtent()
    filter.radius = blurRadius
    guard let output = filter.outputImage?.cropped(to: input.extent),
          let blurred = CIContext().createCGImage(output, from: input.extent)
    else { return image }
    return UIImage(cgImage: blurred, scale: image.scale, orientation: image.imageOrientation)
  }

  /// Installs the configured enter start state before Lynx paints its first
  /// screen. A pushed page starts one full viewport below the clipping bounds,
  /// so none of the new page is visible in its first frame.
  func prepare(content: UIView) {
    applyContent(0, content: content, animation: enterAnimation)
  }

  /// Plays the open choreography once the content painted its first screen.
  func playPresent(content: UIView) {
    guard !presented else { return }
    presented = true
    interactiveDismissReady = false
    apply(0, content: content, animation: enterAnimation)
    guard playsPresentChoreography else {
      apply(1, content: content, animation: enterAnimation)
      interactiveDismissReady = true
      return
    }
    UIView.animate(
      withDuration: Self.duration,
      delay: 0,
      options: [.curveEaseInOut, .allowUserInteraction],
      animations: {
        self.apply(1, content: content, animation: self.enterAnimation)
      },
      completion: { finished in
        self.interactiveDismissReady = finished
      }
    )
  }

  /// Starts a leading-edge interactive dismissal at the fully presented state.
  /// The gesture progress then drives the same independently configured exit
  /// choreography used by a discrete close.
  func beginInteractiveDismiss(content: UIView) -> Bool {
    guard canBeginInteractiveDismiss else { return false }
    interactiveDismissReady = false
    interactiveDismissFraction = 1
    apply(1, content: content, animation: exitAnimation)
    return true
  }

  /// Maps 0...1 gesture progress onto the reverse present choreography.
  func updateInteractiveDismiss(progress: CGFloat, content: UIView) {
    guard interactiveDismissFraction != nil else { return }
    let clampedProgress = min(max(progress, 0), 1)
    let fraction = 1 - clampedProgress
    interactiveDismissFraction = fraction
    apply(fraction, content: content, animation: exitAnimation)
  }

  /// Springs a cancelled interactive dismissal back to the presented state.
  func cancelInteractiveDismiss(content: UIView) {
    guard let fraction = interactiveDismissFraction else { return }
    interactiveDismissFraction = nil
    let duration = max(0.08, Self.duration * TimeInterval(1 - fraction))
    UIView.animate(
      withDuration: duration,
      delay: 0,
      options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction],
      animations: {
        self.apply(1, content: content, animation: self.exitAnimation)
      },
      completion: { finished in
        self.interactiveDismissReady = finished
      }
    )
  }

  /// Completes an interactive dismissal from its current gesture position.
  func finishInteractiveDismiss(content: UIView, completion: @escaping () -> Void) {
    guard let fraction = interactiveDismissFraction else {
      playDismiss(content: content, completion: completion)
      return
    }
    interactiveDismissFraction = nil
    interactiveDismissReady = false
    let duration = max(0.08, Self.duration * TimeInterval(fraction))
    UIView.animate(
      withDuration: duration,
      delay: 0,
      options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction],
      animations: {
        self.apply(0, content: content, animation: self.exitAnimation)
      },
      completion: { _ in completion() }
    )
  }

  /// Reverses the open choreography and reports completion, so the page can
  /// pop over a fullscreen, pixel-aligned snapshot with no system animation.
  /// Before the first screen there is nothing to animate.
  func playDismiss(content: UIView, completion: @escaping () -> Void) {
    interactiveDismissReady = false
    interactiveDismissFraction = nil
    guard presented else {
      completion()
      return
    }
    guard playsDismissChoreography else {
      completion()
      return
    }
    // Every phase resolves to identity + alpha 1 at fraction 1, so selecting a
    // different exit configuration here cannot jump the currently shown page.
    apply(1, content: content, animation: exitAnimation)
    UIView.animate(
      withDuration: Self.duration,
      delay: 0,
      options: [.curveEaseInOut, .beginFromCurrentState, .allowUserInteraction],
      animations: { self.apply(0, content: content, animation: self.exitAnimation) }
    ) { _ in
      completion()
    }
  }

  private func apply(
    _ fraction: CGFloat,
    content: UIView,
    animation: PresentContentAnimationOptions
  ) {
    if playsBackdropTransition {
      let scale = 1 - Self.backdropShift * fraction
      // ty shifts down by half the scale shift: exactly cancels the scale's
      // bottom inset, so the snapshot's bottom edge stays flush with the
      // screen bottom (no black gap) while its top edge drops below the
      // status bar.
      view.transform = CGAffineTransform(
        a: scale, b: 0, c: 0, d: scale,
        tx: 0, ty: view.bounds.height * Self.backdropShift / 2 * fraction
      )
      applyLegacyCornerRadius(fraction)
    }
    scrim.alpha = (playsBackdropTransition || animation.isEnabled) ? fraction : 1
    applyContent(fraction, content: content, animation: animation)
  }

  private func applyContent(
    _ fraction: CGFloat,
    content: UIView,
    animation: PresentContentAnimationOptions
  ) {
    content.alpha = animation.opacity ? fraction : 1
    content.transform = animation.push
      ? CGAffineTransform(
        translationX: 0,
        y: content.bounds.height * (1 - fraction)
      )
      : .identity
  }

  private func applyLegacyCornerRadius(_ fraction: CGFloat) {
    if #available(iOS 26.0, *) {
      return
    }
    view.layer.cornerRadius = Self.legacyCornerRadius * fraction
  }
}
