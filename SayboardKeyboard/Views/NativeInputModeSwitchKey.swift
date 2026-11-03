import SwiftUI
import UIKit

/// Native system Globe picker. The separate Emoji key opens Altboard's
/// offline Emoji page; UIKit owns the OS keyboard-switch touch events.
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
    button.accessibilityLabel = "System keyboard picker"
    button.accessibilityHint = "Tap or hold to switch between installed keyboards."
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
    let ink: UIColor = colorScheme == .dark ? .white : .black
    let configuration = UIImage.SymbolConfiguration(
      pointSize: Self.iconSize, weight: .regular
    )
    return (UIImage(systemName: "globe", withConfiguration: configuration)
      ?? UIImage()).withTintColor(ink, renderingMode: .alwaysOriginal)
  }
}
