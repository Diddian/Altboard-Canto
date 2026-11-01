
import UIKit

@MainActor
enum KeyboardMetrics {

  static let baseHeight: CGFloat = 240
  static let baseExtendedHeight: CGFloat = 289.5
  static let baseActionBarExtra: CGFloat = 42

  static var heightFactor: CGFloat {
    CGFloat(SharedSettings().keyboardHeightScale)
  }

  static var isCompactStandard: Bool {
    heightFactor < 0.82
  }

  static var scale: CGFloat {
    (UIDevice.current.userInterfaceIdiom == .pad ? 293 / baseHeight : 1)
      * heightFactor
  }

  static var height: CGFloat {
    (isCompactStandard ? 164 : baseHeight) * scale
  }

  static var extendedHeight: CGFloat {
    baseExtendedHeight * scale
  }

  static let actionBarExtraHeight: CGFloat = baseActionBarExtra * scale

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
