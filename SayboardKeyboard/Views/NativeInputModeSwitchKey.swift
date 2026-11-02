import SwiftUI
import UIKit

/// Apple-supported system keyboard picker. A tap advances keyboards; touching
/// and holding the same button presents enabled keyboards, including Emoji.
/// There is no public API to jump straight to the Emoji input mode.
struct NativeInputModeSwitchKey: UIViewRepresentable {
  let configure: ((UIButton) -> Void)?

  func makeUIView(context: Context) -> UIButton {
    let button = UIButton(type: .system)
    button.setImage(UIImage(systemName: "globe"), for: .normal)
    button.setPreferredSymbolConfiguration(
      UIImage.SymbolConfiguration(pointSize: 20, weight: .regular),
      forImageIn: .normal
    )
    button.tintColor = .label
    button.backgroundColor = KeyboardPalette.keyFill
    button.layer.cornerRadius = KeyboardChromeMetrics.keyCornerRadius
    button.isAccessibilityElement = true
    button.accessibilityLabel = "Change keyboard"
    button.accessibilityHint = "Touch and hold to choose the system Emoji keyboard"
    // UIInputViewController's selector owns both taps and long-press menus.
    configure?(button)
    return button
  }

  func updateUIView(_ button: UIButton, context: Context) {
    button.tintColor = .label
    button.backgroundColor = KeyboardPalette.keyFill
  }
}
