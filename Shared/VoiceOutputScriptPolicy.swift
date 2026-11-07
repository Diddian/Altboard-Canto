import Foundation

/// Prevent the app's default HK Traditional conversion from overriding a
/// user-selected Simplified Chinese output target.
enum VoiceOutputScriptPolicy {
  static func simplify(_ text: String) -> String {
    text.applyingTransform(StringTransform("Hant-Hans"), reverse: false) ?? text
  }
}
