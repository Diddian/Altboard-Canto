import Testing

@Suite("Latin keyboard long-press alternatives")
struct LetterKeyAlternatesTests {
  @Test func germanCharacters() {
    #expect(LetterKeyAlternates.choices(for: "A", uppercase: false).contains("ä"))
    #expect(LetterKeyAlternates.choices(for: "O", uppercase: true).contains("Ö"))
    #expect(LetterKeyAlternates.choices(for: "S", uppercase: true).contains("ẞ"))
    #expect(LetterKeyAlternates.choices(for: "U", uppercase: false).contains("ü"))
  }

  @Test func extendedLatinAndSymbolVariants() {
    #expect(LetterKeyAlternates.holdChoices(
      for: "h", uppercase: false
    ).contains("ħ"))
    #expect(LetterKeyAlternates.holdChoices(
      for: "k", uppercase: false
    ).contains("ķ"))
    #expect(LetterKeyAlternates.holdChoices(
      for: "l", uppercase: false
    ).contains("ľ"))
    #expect(LetterKeyAlternates.holdChoices(
      for: "d", uppercase: false
    ).contains("ď"))
    #expect(SymbolKeyAlternates.choices(for: "$").contains("€"))
    #expect(SymbolKeyAlternates.choices(for: "-").contains("—"))
    #expect(SymbolKeyAlternates.choices(for: "/").contains("\\"))
    #expect(SymbolKeyAlternates.choices(for: "2").contains("²"))
    #expect(SymbolKeyAlternates.choices(for: "?").contains("？"))
  }

  @Test func holdNeverInsertsBaseLetter() {
    let alternatives = LetterKeyAlternates.holdChoices(
      for: "h", uppercase: false, secondary: LetterKeySecondary.symbol(row: 1, index: 5)
    )
    #expect(alternatives == ["$"])
    #expect(!alternatives.contains("h"))
    #expect(LetterKeySecondary.symbol(row: 1, index: 8) == "\"")
    #expect(LetterKeySecondary.symbol(row: 2, index: 0) == ")")
    #expect(LetterKeyAlternates.holdChoices(for: "u", uppercase: false,
                                            secondary: "7").contains("ü"))
  }

  @Test func popupVisualDirectionMatchesFinger() {
    #expect(LetterHoldNavigation.visualOrder(count: 4, expandsLeft: true) == [3, 2, 1, 0])
    #expect(LetterHoldNavigation.selectedIndex(initialX: 100, currentX: 36,
      expandsLeft: true, count: 4, step: 32) == 2)
    #expect(LetterHoldNavigation.selectedIndex(initialX: 100, currentX: 164,
      expandsLeft: false, count: 4, step: 32) == 2)
  }

  @Test func plainLetterHasNoAlternates() {
    #expect(LetterKeyAlternates.choices(for: "Q", uppercase: false) == ["q"])
    #expect(LetterKeyAlternates.choices(for: "Q", uppercase: true) == ["Q"])
  }
}
