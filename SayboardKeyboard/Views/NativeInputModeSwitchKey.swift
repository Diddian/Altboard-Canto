import SwiftUI
import UIKit

/// Native system keyboard switcher, including the system Emoji keyboard.
/// UIKit owns the picker gesture; no custom Emoji catalog is mounted.
struct NativeInputModeSwitchKey: UIViewRepresentable {
  @Environment(\.colorScheme) private var colorScheme
  let configure: ((UIButton) -> Void)?
  var iconName = "face.smiling"

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
    button.accessibilityLabel = self.iconName == "globe"
      ? "System keyboard picker" : "Keyboard and Emoji picker"
    button.accessibilityHint = "Hold to choose the system Emoji keyboard or another keyboard."
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
      colorScheme: self.colorScheme, iconName: self.iconName
    )
  }

  private static func glyphImage(colorScheme: ColorScheme, iconName: String) -> UIImage {
    let ink: UIColor = colorScheme == .dark ? .white : .black
    let configuration = UIImage.SymbolConfiguration(
      pointSize: Self.iconSize, weight: .regular
    )
    return (UIImage(systemName: iconName, withConfiguration: configuration)
      ?? UIImage(systemName: "globe", withConfiguration: configuration)
      ?? UIImage()).withTintColor(ink, renderingMode: .alwaysOriginal)
  }
}
