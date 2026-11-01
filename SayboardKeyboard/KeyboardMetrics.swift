
import UIKit

@MainActor
enum KeyboardMetrics {

  static let baseHeight: CGFloat = 260
  static let baseExtendedHeight: CGFloat = 289.5
  static let baseActionBarExtra: CGFloat = 42

  static var heightFactor: CGFloat {
    CGFloat(SharedSettings().keyboardHeightScale)
  }

  /// Compact mode uses a space-bar-shaped microphone between side keys.
  static var isCompactStandard: Bool {
    heightFactor < 0.90
  }

  static let standardMicDiameter: CGFloat = 96
  static let rowGap: CGFloat = 6
  static let baseCompactHeight: CGFloat = 150

  /// Height changes whitespace, not key sizes.
  static var scale: CGFloat {
    UIDevice.current.userInterfaceIdiom == .pad ? 293 / baseHeight : 1
  }

  static var height: CGFloat {
    let factor = max(0.70, min(1.10, heightFactor))
    if factor < 0.90 {
      // 70% = 150pt; just below 90% = 234pt. All keys remain 45pt.
      return (baseCompactHeight + (factor - 0.70) * 420) * scale
    }
    return baseHeight * factor * scale
  }

  static var extendedHeight: CGFloat {
    max(284 * scale, baseExtendedHeight * heightFactor * scale)
  }

  static var actionBarExtraHeight: CGFloat {
    baseActionBarExtra * scale
  }

  static func totalHeight(actionBarVisible: Bool, kind: KeyboardKind) -> CGFloat {
    let base = kind == .extended ? self.extendedHeight : self.height
    return base + (actionBarVisible ? self.actionBarExtraHeight : 0)
  }
}

extension CGFloat {
  @MainActor
  var kbScaled: CGFloat {
    self * KeyboardMetrics.scale
  }
}

extension Double {
  @MainActor
  var kbScaled: CGFloat {
    CGFloat(self) * KeyboardMetrics.scale
  }
}

extension Int {
  @MainActor
  var kbScaled: CGFloat {
    CGFloat(self) * KeyboardMetrics.scale
  }
}
