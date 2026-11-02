import Foundation

/// One fixed iPhone keyboard geometry policy for both the real extension
/// and the main-app previews. No user-adjustable height multiplier exists.
enum KeyboardLayoutGeometry {
  static let microphoneDefaultHeight: CGFloat = 260
  static let microphoneCompactHeight: CGFloat = 150
  static let fullTypingHeight: CGFloat = 312

  static let keyHeight: CGFloat = 45
  static let keySpacing: CGFloat = 6
  static let alphabetRowSpacing: CGFloat = 11
  static let alphabetEdgeInset: CGFloat = 6.67
  static let alphabetSecondInset: CGFloat = 28
  static let alphabetSpecialGap: CGFloat = 14.67
  static let alphabetToolbarTopInset: CGFloat = 7
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
