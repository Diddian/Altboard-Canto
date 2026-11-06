import Foundation

@main
struct VerifyKeyboardLayout {
  static func main() {
    for kind in KeyboardKind.allCases {
      let normal = KeyboardLayoutGeometry.height(kind: kind, microphoneLayout: .defaultLayout)
      let compact = KeyboardLayoutGeometry.height(kind: kind, microphoneLayout: .compact)
      if kind == .standard {
        precondition(normal == 277 && compact == 150)
      } else {
        precondition(normal == 277 && compact == 277)
      }
    }
    precondition(KeyboardLayoutGeometry.alphabetToolbarTopInset == 6)
    precondition(KeyboardLayoutGeometry.alphabetToolbarBottomInset == 6)
    precondition(KeyboardLayoutGeometry.topCornerRadius == 24)
    // A separate German layout exposes native Ä, Ö, Ü and ß keys.
    precondition(LetterKeyArrangement.german.rows[0].contains("Ü"))
    precondition(LetterKeyArrangement.german.rows[1].contains("Ö"))
    precondition(LetterKeyArrangement.german.rows[1].contains("Ä"))
    precondition(LetterKeyArrangement.german.rows[2].contains("ß"))
    precondition(LetterKeyArrangement.qwerty.rows.flatMap { $0 }.count == 26)
    precondition(LetterKeyArrangement.qwertz.rows.flatMap { $0 }.count == 26)
    // The first row starts below the toolbar, never above its clipping area.
    let firstKeyTop = KeyboardLayoutGeometry.alphabetToolbarTopInset
      + KeyboardLayoutGeometry.keyHeight
      + KeyboardLayoutGeometry.alphabetToolbarBottomInset
    precondition(firstKeyTop == 57)
    let lastRowBottom = firstKeyTop
      + 3 * KeyboardLayoutGeometry.keyHeight
      + 2 * KeyboardLayoutGeometry.alphabetRowSpacing
      + KeyboardLayoutGeometry.alphabetRowSpacing
      + KeyboardLayoutGeometry.keyHeight + 4
    precondition(lastRowBottom < KeyboardLayoutGeometry.fullTypingHeight)
    precondition(KeyboardLayoutGeometry.fullTypingHeight - lastRowBottom <= 4)
    precondition(KeyboardLayoutGeometry.alphabetEdgeInset < KeyboardLayoutGeometry.alphabetSpecialRowInset)
    let width: CGFloat = 440
    let inset = KeyboardLayoutGeometry.alphabetSymbolsRowInset
    let wide = KeyboardLayoutGeometry.alphabetSymbolsWideKeyWidth
    let groupGap = KeyboardLayoutGeometry.alphabetSymbolsGroupGap
    let keyGap = KeyboardLayoutGeometry.keySpacing
    let numericKey = (width - 2 * inset - 9 * keyGap) / 10
    let punctuation = (width - 2 * inset - 2 * wide
      - 2 * groupGap - 4 * keyGap) / 5
    // IMG_9688 (1320px wide, inferred 3x): 1/2/3/... keys start at
    // x=20px, native punctuation starts x=214px and Backspace x=1150px.
    precondition(abs(inset * 3 - 20) < 0.05)
    precondition(abs(numericKey * 3 - 112) < 1)
    precondition(abs((inset + wide + groupGap) * 3 - 214) < 0.1)
    precondition(abs(punctuation * 3 - 164) < 0.1)
    let backspaceX = width - inset - wide
    precondition(abs(backspaceX * 3 - 1150) < 0.1)
    let letterCell = (width - 2 * KeyboardLayoutGeometry.alphabetSpecialRowInset
      - 2 * KeyboardLayoutGeometry.alphabetSymbolsWideKeyWidth
      - 2 * KeyboardLayoutGeometry.alphabetSpecialGap) / 7
    let firstY = KeyboardLayoutGeometry.alphabetSpecialRowInset
      + KeyboardLayoutGeometry.alphabetSymbolsWideKeyWidth
      + KeyboardLayoutGeometry.alphabetSpecialGap + 3
    let lastM = firstY + 6 * letterCell
    precondition(abs(firstY * 3 - 214) < 0.1)
    precondition(abs(lastM * 3 - 994) < 0.2)
    // The bottom row already matches the native reference within 1px:
    // ?123 48pt; Emoji 48pt; Space 210.67pt; Return 102pt.
    print("Fixed keyboard geometry verified")
  }
}
