import Foundation

@main
enum UniversalCantoneseSmoke {
  static func main() {
    precondition(CantoneseSyllableEditing.yaleAlias("jyu5") == "yu")
    precondition(CantoneseSyllableEditing.yaleAlias("jyun4") == "yun")
    precondition(CantoneseSyllableEditing.yaleAlias("jyut6") == "yut")
    precondition(CantoneseSyllableEditing.sidneyLauAlias("zoeng1") == "jeung")
    precondition(CantoneseSyllableEditing.sidneyLauAlias("goeng1") == "geung")
    precondition(CantoneseRomanizationVariants.variants(for: "mm") == ["mm", "m"])
    precondition(CantoneseRomanizationVariants.variants(for: "ng") == ["ng", "m"])
    precondition(CantoneseRomanizationVariants.variants(for: "yyu") == ["yyu", "yu"])
    precondition(CantoneseRomanizationVariants.variants(for: "gamyuen") == ["gamyuen"])
    // Regression: accidental string substitution may corrupt a real final.
    precondition(CantoneseSyllableEditing.sidneyLauAlias("soeng2") == "seung")
    precondition(CantoneseSyllableEditing.sidneyLauAlias("ceon1") == "chun")
    precondition(CantoneseSyllableEditing.sidneyLauAlias("keoi5") == "kui")
    precondition(CantoneseSyllableEditing.sidneyLauAlias("jyun4") == "yuen")
    precondition(CantoneseSyllableEditing.sidneyLauAlias("jyut6") == "yuet")
    precondition(CantoneseRomanizationVariants.variants(for: String(repeating: "a", count: 49)).isEmpty)
    let cases: [(String, String, Int)] = [
      ("jui", "zeoi3", 3), ("sui", "seoi2", 3), ("yuen", "jyun4", 4),
      ("gamyuen", "gam1 jyun4", 4), ("gamyat", "gam1 jat6", 3),
      ("gamjat", "gam1 jat6", 3), ("yuet", "jyut6", 4),
      ("huet", "hyut3", 4), ("sue", "syu1", 3),
    ]
    for (typed, canonical, length) in cases {
      precondition(CantoneseSyllableEditing.lastSyllableLength(
        typed: typed, canonical: canonical
      ) == length, "Unexpected phonetic deletion: \(typed)")
    }
    precondition(CantoneseSyllableEditing.lastSyllableLength(
      typed: "unrelated", canonical: "jyun4"
    ) == nil)
    print("Universal Cantonese variants and safe deletion: PASS")
  }
}
