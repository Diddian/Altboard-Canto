import Foundation

@main
struct VerifyKeyboardLayout {
  static func main() {
    for kind in KeyboardKind.allCases {
      let normal = KeyboardLayoutGeometry.height(kind: kind, microphoneLayout: .defaultLayout)
      let compact = KeyboardLayoutGeometry.height(kind: kind, microphoneLayout: .compact)
      if kind == .standard {
        precondition(normal == 260 && compact == 150)
      } else {
        precondition(normal == 288 && compact == 288)
      }
    }
    // The first row starts below the toolbar, never above its clipping area.
    let firstKeyTop = KeyboardLayoutGeometry.alphabetToolbarTopInset
      + KeyboardLayoutGeometry.keyHeight
      + KeyboardLayoutGeometry.alphabetToolbarBottomInset
    precondition(firstKeyTop > 0)
    let lastRowBottom = firstKeyTop
      + 3 * KeyboardLayoutGeometry.keyHeight
      + 2 * KeyboardLayoutGeometry.alphabetRowSpacing
      + KeyboardLayoutGeometry.alphabetRowSpacing
      + KeyboardLayoutGeometry.keyHeight + 4
    precondition(lastRowBottom < KeyboardLayoutGeometry.fullTypingHeight)
    precondition(KeyboardLayoutGeometry.fullTypingHeight - lastRowBottom <= 12)
    print("Fixed keyboard geometry verified")
  }
}
