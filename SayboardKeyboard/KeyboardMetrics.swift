import UIKit

/// Stable iPhone keyboard canvas. The old height slider caused the host
/// UIInputView and its SwiftUI rows to negotiate mismatched heights.
@MainActor
enum KeyboardMetrics {

  static let baseHeight = KeyboardLayoutGeometry.fullTypingHeight
  static let baseExtendedHeight = KeyboardLayoutGeometry.fullTypingHeight
  static let baseCompactHeight = KeyboardLayoutGeometry.microphoneCompactHeight
  // Retain historical iPad scaling independently of the iPhone height policy.
  private static let ipadScaleReferenceHeight: CGFloat = 260
  static let standardMicDiameter: CGFloat = 96
  static let rowGap: CGFloat = 6

  static var isCompactStandard: Bool {
    SharedSettings().microphoneKeyboardLayout == .compact
  }

  /// iPhone keys remain at the native 45pt size. The existing iPad
  /// accommodation is preserved; it no longer depends on user settings.
  static var scale: CGFloat {
    UIDevice.current.userInterfaceIdiom == .pad ? 293 / ipadScaleReferenceHeight : 1
  }

  static var height: CGFloat {
    totalHeight(actionBarVisible: false, kind: .standard)
  }

  static var extendedHeight: CGFloat {
    totalHeight(actionBarVisible: false, kind: .extended)
  }

  /// Opening the AI action overlay must not raise or resize the host keyboard.
  /// Mode changes are the only user-requested height changes.
  static func totalHeight(actionBarVisible _: Bool, kind: KeyboardKind) -> CGFloat {
    KeyboardLayoutGeometry.height(
      kind: kind, microphoneLayout: SharedSettings().microphoneKeyboardLayout
    ) * scale
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
