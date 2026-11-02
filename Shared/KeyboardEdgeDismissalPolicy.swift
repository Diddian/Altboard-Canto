import Foundation

/// Pure threshold rules, independent of the keyboard extension lifecycle.
enum KeyboardEdgeDismissalPolicy {
  static let activationBand: CGFloat = 22
  static let minimumDistance: CGFloat = 56
  static let quickFlickDistance: CGFloat = 28
  static let quickFlickVelocity: CGFloat = 650

  static func acceptsTouch(atTopY y: CGFloat) -> Bool {
    y >= 0 && y <= activationBand
  }

  static func isDownward(translation: CGPoint) -> Bool {
    translation.y > 0 && translation.y > abs(translation.x) * 1.15
  }

  static func visualProgress(translation: CGPoint) -> CGFloat {
    guard isDownward(translation: translation) else { return 0 }
    return min(1, max(0, translation.y / 140))
  }

  static func shouldDismiss(translation: CGPoint, verticalVelocity: CGFloat) -> Bool {
    guard isDownward(translation: translation) else { return false }
    return translation.y >= minimumDistance
      || (translation.y >= quickFlickDistance && verticalVelocity >= quickFlickVelocity)
  }
}
