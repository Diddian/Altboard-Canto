import Foundation

@main
enum VerifyVoicePunctuation {
  static func main() {
    let chinese = "你好，世界！今日點呀？"
    precondition(VoicePunctuationPolicy.render(chinese, enabled: true) == chinese)
    precondition(VoicePunctuationPolicy.render(chinese, enabled: false) == "你好 世界 今日點呀")
    precondition(VoicePunctuationPolicy.render("Hello, world! How are you?", enabled: false)
      == "Hello world How are you")
    precondition(VoicePunctuationPolicy.render("Hallo,\nWelt!  Wie geht's?", enabled: false)
      == "Hallo Welt Wie geht's")
    precondition(VoicePunctuationPolicy.render("Don't stop. O’Neill said: 3.5 GB and 3,5 GB.", enabled: false)
      == "Don't stop O’Neill said 3.5 GB and 3,5 GB")
    precondition(VoicePunctuationPolicy.render("‘quoted’ and hello.world", enabled: false)
      == "quoted and hello world")
    precondition(VoicePunctuationPolicy.render("  ! ?  ", enabled: false).isEmpty)
    precondition(VoicePunctuationPolicy.render("One two", enabled: false) == "One two")
    print("Voice punctuation final-output policy passed")
  }
}
