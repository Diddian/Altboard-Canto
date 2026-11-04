import Foundation
@main
struct VerifyLetterHoldAlternates {
  static func main() {
    let a = LetterKeyAlternates.choices(for: "a", uppercase: false, secondary: "1")
    precondition(a.first == "a" && a[1] == "1" && a.contains("ä"))
    let u = LetterKeyAlternates.choices(for: "u", uppercase: true, secondary: "7")
    precondition(u.first == "U" && u[1] == "7" && u.contains("Ü"))
    precondition(LetterKeySecondary.symbol(row: 0, index: 0) == "1")
    precondition(LetterKeySecondary.symbol(row: 2, index: 3) == "?")
    precondition(LetterKeySecondary.symbol(row: 3, index: 0) == nil)
    let h = LetterKeyAlternates.holdChoices(for: "h", uppercase: false,
                                             secondary: LetterKeySecondary.symbol(row: 1, index: 5))
    precondition(h.first == "$" && h.contains("ħ") && !h.contains("h"),
                 "Hold H should retain the dollar symbol and accented alternatives")
    let l = LetterKeyAlternates.holdChoices(for: "l", uppercase: false,
                                             secondary: LetterKeySecondary.symbol(row: 1, index: 8))
    precondition(l.first == "\"", "Hold L should insert double quote")
    precondition(LetterKeySecondary.symbol(row: 2, index: 0) == ")")
    let accents = LetterKeyAlternates.holdChoices(for: "u", uppercase: false,
                                                    secondary: "7")
    precondition(accents.first == "7" && accents.contains("ü"))
    precondition(LetterHoldNavigation.visualOrder(count: 3, expandsLeft: true) == [2,1,0])
    precondition(LetterHoldNavigation.visualOrder(count: 3, expandsLeft: false) == [0,1,2])
    precondition(LetterHoldNavigation.selectedIndex(
      initialX: 200, currentX: 136, expandsLeft: true, count: 3, step: 32) == 2)
    precondition(LetterHoldNavigation.selectedIndex(
      initialX: 200, currentX: 264, expandsLeft: false, count: 3, step: 32) == 2)
    let chineseOpen = SymbolKeyAlternates.choices(for: "[", chinese: true)
    precondition(chineseOpen.first == "[" && chineseOpen.contains("「")
                 && chineseOpen.contains("【"))
    let latinOpen = SymbolKeyAlternates.choices(for: "[")
    precondition(latinOpen.first == "[" && !latinOpen.contains("「"))
    precondition(SymbolKeyAlternates.choices(for: "#", chinese: true).contains("＃"))
    precondition(SymbolKeyAlternates.choices(for: "^", chinese: true).contains("︿"))
    precondition(SymbolKeyAlternates.choices(for: "+", chinese: true).contains("＋"))
    precondition(SymbolKeyAlternates.choices(for: "=", chinese: true).contains("＝"))
    precondition(SymbolKeyAlternates.choices(for: "]", chinese: true).contains("」"))
    let apostrophe = SymbolKeyAlternates.choices(for: "'", chinese: true)
    precondition(apostrophe.contains("「") && apostrophe.contains("」")
                 && apostrophe.contains("『") && apostrophe.contains("』"))
    precondition(!SymbolKeyAlternates.choices(for: "'").contains("「"))
    let quotes = SymbolKeyAlternates.choices(for: "\"", chinese: true)
    precondition(quotes.contains("「") && quotes.contains("』"))
    print("Long-press punctuation and context-scoped Chinese alternates: PASS")
  }
}
