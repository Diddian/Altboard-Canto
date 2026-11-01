
import UIKit

@MainActor
enum KeyboardMetrics {

  static let baseHeight: CGFloat = 240
  static let baseExtendedHeight: CGFloat = 289.5
  static let baseActionBarExtra: CGFloat = 42

  static var heightFactor: CGFloat {
    CGFloat(SharedSettings().keyboardHeightScale)
  }

  /// Switch before the 106pt circle could collide with the fixed 45pt keys.
  static var isCompactStandard: Bool {
    heightFactor < 0.90
  }

  /// Height changes whitespace, not key sizes.
  static var scale: CGFloat {
    UIDevice.current.userInterfaceIdiom == .pad ? 293 / baseHeight : 1
  }

  static var height: CGFloat {
    max((isCompactStandard ? 158 : 216) * scale, baseHeight * heightFactor * scale)
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
