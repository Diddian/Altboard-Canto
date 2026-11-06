import Foundation

@main
enum ChineseInputSmoke {
  static func main() {
    precondition(ChineseInputMode.allCases.map(\.rawValue) ==
                 ["phonetic", "quick", "cangjie", "stroke"])
    precondition(ChineseInputMode.phonetic.next == .quick)
    precondition(ChineseInputMode.quick.next == .cangjie)
    precondition(ChineseInputMode.cangjie.next == .stroke)
    precondition(ChineseInputMode.stroke.next == .phonetic)
    precondition(InputMethodCatalog.available(for: ["zh"]).isEmpty)
    precondition(InputMethodCatalog.available(for: ["de", "yue"]).count == 4)
    precondition(InputMethodCatalog.available(for: ["yue", "zh"]).count == 4)
    precondition(ChineseShapeKeys.hint(for: "A", mode: .cangjie) == "日")
    precondition(ChineseShapeKeys.hint(for: "J", mode: .quick) == "十")
    precondition(ChineseShapeKeys.hint(for: "J", mode: .phonetic) == nil)
    precondition(ChineseStrokeKeys.keys.map(\.code) == ["m", "/", ",", ".", "n"])
    precondition(ChineseStrokeKeys.glyphs(for: "m/,n") == "一丨丿乛")
    precondition(ChineseStrokeKeys.alternates.map(\.count) == [8, 8, 8, 3, 4])
    precondition(ChineseStrokeKeys.alternates[0] ==
      ["1", "2", "3", "4", "-", "/", ":", ";"])
    precondition(ChineseStrokeKeys.alternates[1] ==
      ["4", "5", "6", "7", ";", "(", ")", "$"])
    precondition(ChineseStrokeKeys.alternates[2] ==
      ["7", "8", "9", "0", "$", "&", "@", "\""])
    precondition(ChineseStrokeKeys.alternates[3] == ["。", "，", "？"])
    precondition(ChineseStrokeKeys.alternates[4] == ["？", "！", "「", "」"])
    precondition(ChineseStrokeKeys.popupIndex(horizontalDelta: 0, optionCount: 8, columnWidth: 36) == 4)
    precondition(ChineseStrokeKeys.popupIndex(horizontalDelta: 36, optionCount: 8, columnWidth: 36) == 5)
    precondition(ChineseStrokeKeys.popupIndex(horizontalDelta: -36, optionCount: 8, columnWidth: 36) == 3)
    precondition(ChineseStrokeKeys.popupIndex(horizontalDelta: 999, optionCount: 8, columnWidth: 36) == 7)
    precondition(ChineseStrokeKeys.popupIndex(horizontalDelta: -999, optionCount: 8, columnWidth: 36) == 0)
    precondition(ChineseStrokeKeys.popupIndex(horizontalDelta: 0, optionCount: 3, columnWidth: 36) == 1)
    precondition(ChineseStrokeKeys.popupStartIndex(keyIndex: 0, optionCount: 8) == 0)
    precondition(ChineseStrokeKeys.popupStartIndex(keyIndex: 2, optionCount: 8) == 7)
    precondition(ChineseStrokeKeys.alternates[0][0] == "1")
    precondition(ChineseStrokeKeys.alternates[2][7] == "\"")
    precondition(ChineseStrokeKeys.popupIndex(
      horizontalDelta: 0, optionCount: 8, columnWidth: 36,
      startIndex: ChineseStrokeKeys.popupStartIndex(keyIndex: 0, optionCount: 8)
    ) == 0)
    precondition(ChineseStrokeKeys.popupIndex(
      horizontalDelta: 36, optionCount: 8, columnWidth: 36, startIndex: 0
    ) == 1)
    precondition(ChineseStrokeKeys.popupIndex(
      horizontalDelta: 0, optionCount: 8, columnWidth: 36,
      startIndex: ChineseStrokeKeys.popupStartIndex(keyIndex: 2, optionCount: 8)
    ) == 7)
    precondition(ChineseStrokeKeys.popupIndex(
      horizontalDelta: -36, optionCount: 8, columnWidth: 36, startIndex: 7
    ) == 6)
    precondition(ChineseShapeRanking.strokeChoiceBonus(0) == 0)
    precondition(ChineseShapeRanking.strokeChoiceBonus(2) == 16_000)
    precondition(ChineseShapeRanking.preferredVariant([:], mode: .quick) == 3)
    precondition(ChineseShapeRanking.preferredVariant(
      ["quick.5": 8], mode: .quick) == 5)
    precondition(ChineseShapeRanking.preferredVariant(
      ["cangjie.3": 8], mode: .cangjie) == 3)
    print("Chinese mode, stroke keys, radical hints and preference: PASS")
  }
}
