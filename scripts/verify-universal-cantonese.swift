import Foundation

@main
enum UniversalCantoneseSmoke {
  static func main() {
    precondition(CantoneseRomanizationVariants.repeatedNegationBase(for: "sikngsik") == "sik")
    precondition(CantoneseRomanizationVariants.repeatedNegationBase(for: "wuingwui") == "wui")
    precondition(CantoneseRomanizationVariants.repeatedNegationBase(for: "sikmsik") == "sik")
    precondition(CantoneseRomanizationVariants.repeatedNegationBase(for: "daannghai") == nil)
    precondition(CantoneseRomanizationVariants.repeatedNegationBase(for: "long") == nil)
    precondition(CantoneseRomanizationVariants.variants(for: "nghai").contains("mhai"))
    precondition(CantoneseRomanizationVariants.variants(for: "nghaai").contains("mhaai"))
    precondition(!CantoneseRomanizationVariants.variants(for: "ngau").contains("mau"))

    precondition(CantoneseSyllableEditing.yaleAlias("zau6") == "jau")
    precondition(CantoneseSyllableEditing.yaleAlias("caan4") == "chaan")
    precondition(CantoneseSyllableEditing.yaleAlias("faan6") == "faan")
    precondition(CantoneseSyllableEditing.sidneyLauAlias("caan4") == "chaan")
    precondition(CantoneseSyllableEditing.lastSyllableLength(
      typed: "sikngsik", canonical: "sik6 m4 sik6"
    ) == 3)
    precondition(CantoneseSyllableEditing.lastSyllableLength(
      typed: "daannghai", canonical: "daan6 m4 hai6"
    ) == 3)
    precondition(CantoneseSyllableEditing.yaleAlias("jyu5") == "yu")
    precondition(CantoneseSyllableEditing.yaleAlias("jyun4") == "yun")
    precondition(CantoneseSyllableEditing.yaleAlias("jyut6") == "yut")
    precondition(CantoneseSyllableEditing.sidneyLauAlias("zoeng1") == "jeung")
    precondition(CantoneseSyllableEditing.sidneyLauAlias("goeng1") == "geung")
    precondition(CantoneseRomanizationVariants.variants(for: "mm") == ["mm", "m"])
    precondition(CantoneseRomanizationVariants.variants(for: "ng") == ["ng", "m"])
    precondition(CantoneseRomanizationVariants.variants(for: "yyu") == ["yyu", "yu"])
    precondition(CantoneseRomanizationVariants.variants(for: "gamyuen") == ["gamyuen"])
    let maxLength = String(repeating: "a", count: 96)
    precondition(CantoneseRomanizationVariants.variants(for: maxLength) == [maxLength])
    precondition(CantoneseRomanizationVariants.variants(for: String(repeating: "a", count: 97)).isEmpty)
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
