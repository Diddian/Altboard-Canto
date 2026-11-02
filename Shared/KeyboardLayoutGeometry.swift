import Foundation

/// One fixed iPhone keyboard geometry policy for both the real extension
/// and the main-app previews. No user-adjustable height multiplier exists.
enum KeyboardLayoutGeometry {
  static let microphoneDefaultHeight: CGFloat = 260
  static let microphoneCompactHeight: CGFloat = 150
  // 1320x871 native reference at inferred 3x = 290.33pt, including a
  // 20pt bottom inset after the visible fourth key row.
  static let fullTypingHeight: CGFloat = 290

  static let keyHeight: CGFloat = 45
  static let keySpacing: CGFloat = 6
  static let alphabetRowSpacing: CGFloat = 11
  static let alphabetEdgeInset: CGFloat = 6.67
  static let alphabetSecondInset: CGFloat = 28
  static let alphabetSpecialGap: CGFloat = 14.67
  static let alphabetToolbarTopInset: CGFloat = 4
  static let alphabetToolbarBottomInset: CGFloat = 8
  static let alphabetMicWidth: CGFloat = 86

  static func height(
    kind: KeyboardKind,
    microphoneLayout: MicrophoneKeyboardLayout
  ) -> CGFloat {
    switch kind {
    case .standard:
      microphoneLayout == .compact ? microphoneCompactHeight : microphoneDefaultHeight
    case .extended, .alphabetic:
      fullTypingHeight
    }
  }
}
