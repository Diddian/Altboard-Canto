import UIKit

/// Sampled from the supplied iOS reference screenshot (IMG_9659; dark keys #444).
/// One source of truth for both real keyboard and tappable Settings previews.
enum KeyboardPalette {
  static let darkBackdrop = UIColor(red: 31 / 255, green: 31 / 255, blue: 31 / 255, alpha: 1)
  static let backdrop = UIColor { traits in
    traits.userInterfaceStyle == .dark ? darkBackdrop : UIColor(red: 0.875, green: 0.878, blue: 0.902, alpha: 1)
  }
  static let keyFill = UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? UIColor(red: 67 / 255, green: 67 / 255, blue: 67 / 255, alpha: 1)
      : .white
  }
  // Measured from the supplied native prediction-strip screenshot
  // IMG_9670.jpeg at approximately 3x display scale.
  static let suggestionSeparatorWidth: CGFloat = 1
  static let suggestionSeparatorHeight: CGFloat = 24
  static let suggestionSeparator = UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? UIColor(red: 50 / 255, green: 50 / 255, blue: 50 / 255, alpha: 1)
      : UIColor.separator
  }
  static let suggestionGlyph = UIColor { traits in
    traits.userInterfaceStyle == .dark ? UIColor(white: 162.0 / 255.0, alpha: 1) : UIColor.darkText
  }
  static let pressedFill = UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? UIColor(red: 120 / 255, green: 120 / 255, blue: 120 / 255, alpha: 1)
      : UIColor(white: 0.78, alpha: 1)
  }
}
