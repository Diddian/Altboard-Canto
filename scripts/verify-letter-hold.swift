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
    print("Long-press punctuation and umlaut coexist: PASS")
  }
}
