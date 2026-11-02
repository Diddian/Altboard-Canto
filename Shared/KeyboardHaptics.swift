import UIKit

/// Direct UIKit feedback, fired from the actual key event.
@MainActor
enum KeyboardHaptics {
  enum Technique: String, CaseIterable {
    case automatic, selection, soft, light, medium, heavy
    var displayName: String { self.rawValue.capitalized }
  }

  private static let selection = UISelectionFeedbackGenerator()
  private static let soft = UIImpactFeedbackGenerator(style: .soft)
  private static let light = UIImpactFeedbackGenerator(style: .light)
  private static let medium = UIImpactFeedbackGenerator(style: .medium)
  private static let heavy = UIImpactFeedbackGenerator(style: .heavy)

  static func key(
    strength override: Double? = nil,
    enabled overrideEnabled: Bool? = nil,
    technique: Technique = .automatic
  ) {
    let settings = SharedSettings()
    let enabled = overrideEnabled ?? settings.keyboardHapticsEnabled
    let strength = min(1.0, max(0.15, override ?? settings.keyboardHapticStrength))
    let resolved: Technique = if technique == .automatic {
      switch strength {
      case ..<0.30: .selection
      case ..<0.45: .soft
      case ..<0.70: .light
      case ..<0.85: .medium
      default: .heavy
      }
    } else {
      technique
    }
    guard enabled else {
      KeyboardHapticTrace.record(technique: resolved.rawValue, enabled: false, fullAccess: settings.hasFullAccess)
      return
    }
    if resolved == .selection {
      selection.selectionChanged()
      selection.prepare()
    } else {
      let generator: UIImpactFeedbackGenerator = switch resolved {
      case .soft: soft
      case .light: light
      case .medium: medium
      case .heavy: heavy
      case .selection, .automatic: light
      }
      generator.impactOccurred(intensity: CGFloat(strength))
      generator.prepare()
    }
    // UIKit returns no success status. This records attempts, not physical vibration.
    KeyboardHapticTrace.record(technique: resolved.rawValue, enabled: true, fullAccess: settings.hasFullAccess)
  }

  static func prepare() {
    selection.prepare()
    soft.prepare()
    light.prepare()
    medium.prepare()
    heavy.prepare()
  }
}
