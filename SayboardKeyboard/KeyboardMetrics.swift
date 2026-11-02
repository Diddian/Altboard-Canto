import UIKit

/// Stable iPhone keyboard canvas. The old height slider caused the host
/// UIInputView and its SwiftUI rows to negotiate mismatched heights.
@MainActor
enum KeyboardMetrics {

  static let baseHeight = KeyboardLayoutGeometry.microphoneDefaultHeight
  static let baseExtendedHeight = KeyboardLayoutGeometry.fullTypingHeight
  static let baseCompactHeight = KeyboardLayoutGeometry.microphoneCompactHeight
  /// Reference IMG_9692 (1320x983), 3x screen: 328pt native emoji canvas.
  static let emojiReferenceHeight: CGFloat = 328
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
    KeyboardLayoutGeometry.height(
      kind: .standard,
      microphoneLayout: SharedSettings().microphoneKeyboardLayout
    ) * scale
  }

  static var extendedHeight: CGFloat {
    KeyboardLayoutGeometry.fullTypingHeight * scale
  }

  static var emojiHeight: CGFloat { emojiReferenceHeight * scale }

  /// Opening the AI action overlay must not raise or resize the host keyboard.
  /// Mode changes are the only user-requested height changes.
  static func totalHeight(
    actionBarVisible _: Bool, kind: KeyboardKind, emojiVisible: Bool = false
  ) -> CGFloat {
    if emojiVisible { return emojiHeight }
    return kind == .standard ? height : extendedHeight
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
