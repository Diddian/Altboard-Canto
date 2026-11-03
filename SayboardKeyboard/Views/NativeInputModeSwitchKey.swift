import SwiftUI
import UIKit

/// Draws the project's original vector Emoji glyph on the system keyboard
/// selector. UIKit still owns the native picker gesture: public iOS APIs
/// cannot select the Emoji input mode by identifier.
struct NativeInputModeSwitchKey: UIViewRepresentable {
  @Environment(\.colorScheme) private var colorScheme
  let configure: ((UIButton) -> Void)?

  private static let iconTag = 7137
  private static let iconSize: CGFloat = 20.67

  func makeUIView(context: Context) -> UIButton {
    let button = UIButton(type: .system)
    let icon = UIImageView()
    icon.tag = Self.iconTag
    icon.isUserInteractionEnabled = false
    icon.contentMode = .scaleAspectFit
    icon.translatesAutoresizingMaskIntoConstraints = false
    button.addSubview(icon)
    NSLayoutConstraint.activate([
      icon.centerXAnchor.constraint(equalTo: button.centerXAnchor),
      icon.centerYAnchor.constraint(equalTo: button.centerYAnchor),
      icon.widthAnchor.constraint(equalToConstant: Self.iconSize),
      icon.heightAnchor.constraint(equalToConstant: Self.iconSize)
    ])
    button.backgroundColor = KeyboardPalette.keyFill
    button.layer.cornerRadius = KeyboardChromeMetrics.keyCornerRadius
    button.isAccessibilityElement = true
    button.accessibilityLabel = "Emoji and keyboard picker"
    button.accessibilityHint = "Tap to switch keyboards. Touch and hold to select the system Emoji keyboard."
    // Keep only Apple's selector for tap/hold, without a competing recognizer.
    configure?(button)
    updateUIView(button, context: context)
    return button
  }

  func updateUIView(_ button: UIButton, context: Context) {
    button.backgroundColor = KeyboardPalette.keyFill
    // A dedicated noninteractive child avoids UIKit briefly clearing its
    // UIButton image when the native input-mode picker is activated.
    (button.viewWithTag(Self.iconTag) as? UIImageView)?.image = Self.glyphImage(
      colorScheme: self.colorScheme
    )
  }

  private static func glyphImage(colorScheme: ColorScheme) -> UIImage {
    let side = Self.iconSize
    let size = CGSize(width: side, height: side)
    let ink: UIColor = colorScheme == .dark ? .white : .black
    return UIGraphicsImageRenderer(size: size).image { renderer in
      let path = NativeEmojiGlyph().path(in: CGRect(origin: .zero, size: size))
      renderer.cgContext.addPath(path.cgPath)
      renderer.cgContext.setFillColor(ink.cgColor)
      renderer.cgContext.drawPath(using: .eoFill)
    }
  }
}
