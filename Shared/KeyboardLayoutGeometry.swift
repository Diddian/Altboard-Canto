import Foundation

/// One fixed iPhone keyboard geometry policy for both the real extension
/// and the main-app previews. No user-adjustable height multiplier exists.
enum KeyboardLayoutGeometry {
  static let microphoneDefaultHeight: CGFloat = 260
  static let microphoneCompactHeight: CGFloat = 150
  // In the supplied iPhone screenshots the Altboard keys end about 13pt
  // above Apple's keys. Keep the 274pt measured content and a 3pt inset.
  static let fullTypingHeight: CGFloat = 277

  static let keyHeight: CGFloat = 45
  static let keySpacing: CGFloat = 6
  static let alphabetRowSpacing: CGFloat = 11
  static let alphabetEdgeInset: CGFloat = 3.67
  static let alphabetSecondInset: CGFloat = 25
  static let alphabetSpecialRowInset: CGFloat = 6.67
  static let alphabetSpecialGap: CGFloat = 14.67
  static let alphabetSymbolsRowInset: CGFloat = 6.67
  static let alphabetSymbolsWideKeyWidth: CGFloat = 50
  static let alphabetSymbolsGroupGap: CGFloat = 14.67
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
