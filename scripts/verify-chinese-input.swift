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
    precondition(ChineseStrokeKeys.punctuation.prefix(4) == ["1", "2", "3", "4"])
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
