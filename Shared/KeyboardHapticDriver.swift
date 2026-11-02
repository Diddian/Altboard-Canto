import Foundation

/// Selectable haptic implementation. Keep UIKit for comparison with the
/// original SwiftUI implementation and a public Core Haptics fallback.
enum KeyboardHapticDriver: String, CaseIterable, Sendable {
  case coreHaptics
  case sensoryFeedback
  case uiKit

  var displayName: String {
    switch self {
    case .coreHaptics: "Core Haptics"
    case .sensoryFeedback: "SwiftUI (original Altboard)"
    case .uiKit: "UIKit (legacy)"
    }
  }
}
