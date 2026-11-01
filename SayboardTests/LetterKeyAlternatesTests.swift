import Testing

@Suite("Latin keyboard long-press alternatives")
struct LetterKeyAlternatesTests {
  @Test func germanCharacters() {
    #expect(LetterKeyAlternates.choices(for: "A", uppercase: false).contains("ä"))
    #expect(LetterKeyAlternates.choices(for: "O", uppercase: true).contains("Ö"))
    #expect(LetterKeyAlternates.choices(for: "S", uppercase: true).contains("ẞ"))
    #expect(LetterKeyAlternates.choices(for: "U", uppercase: false).contains("ü"))
  }

  @Test func plainLetterHasNoAlternates() {
    #expect(LetterKeyAlternates.choices(for: "Q", uppercase: false) == ["q"])
    #expect(LetterKeyAlternates.choices(for: "Q", uppercase: true) == ["Q"])
  }
}
