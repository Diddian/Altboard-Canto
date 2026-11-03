import Foundation

@main
enum VerifyKeyboardCore {
  static func main() {
    precondition(SentenceCapitalization.shouldUseUppercase(after: nil))
    precondition(EnglishCaseSuggestion.replacement(for: "ok") == "OK")
    precondition(EnglishCaseSuggestion.replacement(for: "Ok") == "OK")
    precondition(EnglishCaseSuggestion.replacement(for: "OK") == nil)
    precondition(EnglishCaseSuggestion.replacement(for: "okay") == nil)
    precondition(SentenceCapitalization.shouldUseUppercase(after: "Hello. "))
    precondition(SentenceCapitalization.shouldUseUppercase(after: "Hello\n  "))
    precondition(!SentenceCapitalization.shouldUseUppercase(after: "Hello there"))
    var buffer = JyutpingComposition()
    for char in ["n", "e", "i", "5", "h", "o", "u", "2"] {
      precondition(buffer.append(char))
    }
    precondition(buffer.buffer == "nei5hou2")
    precondition(buffer.backspace())
    precondition(buffer.buffer == "nei5hou")
    precondition(CantoneseSyllableEditing.lastSyllableLength(typed: "gamyat", canonical: "gam1 jat6") == 3)
    precondition(CantoneseSyllableEditing.lastSyllableLength(typed: "gamjat", canonical: "gam1 jat6") == 3)
    precondition(CantoneseSyllableEditing.lastSyllableLength(typed: "gam1jat6", canonical: "gam1 jat6") == 4)
    precondition(CantoneseSyllableEditing.lastSyllableLength(typed: "gamyzt", canonical: "gam1 jat6") == nil)
    precondition(CantoneseSyllableEditing.lastSyllableLength(typed: "hello", canonical: "gam1 jat6") == nil)
    precondition(!buffer.append("."))
    buffer.clear()
    for _ in 0..<96 { precondition(buffer.append("a")) }
    precondition(buffer.buffer.count == 96)
    precondition(!buffer.append("a"))
    buffer.clear()
    precondition(!buffer.backspace() && buffer.isEmpty)
    precondition(LiveCantoneseSafety.matches(buffer: "gamyat", hostContext: "Hello Gamyat"))
    precondition(!LiveCantoneseSafety.matches(buffer: "gamyat", hostContext: "Hello gamya"))
    precondition(!LiveCantoneseSafety.canDeleteAsToken(buffer: "hello", candidateCount: 0, hostContext: "hello"))
    precondition(LiveCantoneseSafety.canDeleteAsToken(buffer: "gamyat", candidateCount: 1, hostContext: "gamyat"))
    print("Keyboard core smoke test passed")
  }
}
