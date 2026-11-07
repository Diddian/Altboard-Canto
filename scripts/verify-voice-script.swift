import Foundation

@main
enum VerifyVoiceScript {
  static func main() {
    precondition(VoiceOutputScriptPolicy.simplify("廁所") == "厕所")
    precondition(VoiceOutputScriptPolicy.simplify("香港廣東話") == "香港广东话")
    precondition(VoiceOutputScriptPolicy.simplify("Hello Berlin") == "Hello Berlin")
    print("Simplified Chinese script output passed")
  }
}
