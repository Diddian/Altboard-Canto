import Foundation

@main
enum VerifyKeyboardCore {
  static func main() {
    precondition(SentenceCapitalization.shouldUseUppercase(after: nil))
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
    precondition(!buffer.append("."))
    buffer.clear()
    precondition(!buffer.backspace() && buffer.isEmpty)
    print("Keyboard core smoke test passed")
  }
}
