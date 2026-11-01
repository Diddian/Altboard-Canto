import UIKit

/// UIKit feedback at the key event, not a SwiftUI view-state observer.
/// Shared by keyboard extension and interactive Settings preview.
@MainActor
enum KeyboardHaptics {
  private static let light = UIImpactFeedbackGenerator(style: .light)
  private static let medium = UIImpactFeedbackGenerator(style: .medium)
  private static let heavy = UIImpactFeedbackGenerator(style: .heavy)

  static func key(strength override: Double? = nil, enabled overrideEnabled: Bool? = nil) {
    let settings = SharedSettings()
    guard overrideEnabled ?? settings.keyboardHapticsEnabled else { return }
    let strength = min(1.0, max(0.15, override ?? settings.keyboardHapticStrength))
    let generator: UIImpactFeedbackGenerator
    switch strength {
    case ..<0.38: generator = light
    case ..<0.74: generator = medium
    default: generator = heavy
    }
    generator.prepare()
    generator.impactOccurred(intensity: CGFloat(strength))
    generator.prepare()
  }

  static func prepare() {
    light.prepare()
    medium.prepare()
    heavy.prepare()
  }
}
