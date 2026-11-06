import UIKit

extension KeyboardViewController {
  /// UITextDocumentProxy exposes only character offsets, not host line
  /// rectangles. Navigate physical newlines when the needed context exists.
  /// Never infer a soft-wrap line from an arbitrary host's text field.
  func moveCursorVertically(_ steps: Int) {
    guard steps != 0 else { return }
    let proxy = self.textDocumentProxy
    guard let document = self.availableDocumentIdentifier() else {
      self.resetCursorVerticalState()
      return
    }
    if self.cursorPreferredDocumentID != document {
      self.resetCursorVerticalState()
    }
    let direction = steps < 0 ? -1 : 1
    for _ in 0..<min(6, abs(steps)) {
      guard let movement = CursorLineNavigation.move(
        direction: direction,
        before: proxy.documentContextBeforeInput,
        after: proxy.documentContextAfterInput,
        preferredColumn: self.cursorPreferredColumn
      ), movement.characterOffset != 0 else { break }
      proxy.adjustTextPosition(byCharacterOffset: movement.characterOffset)
      self.cursorPreferredColumn = movement.preferredColumn
      self.cursorPreferredDocumentID = document
    }
  }

  func resetCursorVerticalState() {
    self.cursorPreferredColumn = nil
    self.cursorPreferredDocumentID = nil
  }
}
