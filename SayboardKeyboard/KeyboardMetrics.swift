import UIKit

/// Stable iPhone keyboard canvas. The old height slider caused the host
/// UIInputView and its SwiftUI rows to negotiate mismatched heights.
@MainActor
enum KeyboardMetrics {

  static let baseHeight: CGFloat = 260
  static let baseExtendedHeight: CGFloat = 312
  static let baseCompactHeight: CGFloat = 150
  static let standardMicDiameter: CGFloat = 96
  static let rowGap: CGFloat = 6

  static var isCompactStandard: Bool {
    SharedSettings().microphoneKeyboardLayout == .compact
  }

  /// iPhone keys remain at the native 45pt size. The existing iPad
  /// accommodation is preserved; it no longer depends on user settings.
  static var scale: CGFloat {
    UIDevice.current.userInterfaceIdiom == .pad ? 293 / baseHeight : 1
  }

  static var height: CGFloat {
    (isCompactStandard ? baseCompactHeight : baseHeight) * scale
  }

  static var extendedHeight: CGFloat {
    baseExtendedHeight * scale
  }

  /// Opening the AI action overlay must not raise or resize the host keyboard.
  /// Mode changes are the only user-requested height changes.
  static func totalHeight(actionBarVisible _: Bool, kind: KeyboardKind) -> CGFloat {
    kind == .standard ? height : extendedHeight
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
