import Foundation

/// Fixed teaching examples checked against the bundled shape table sources.
/// A response only suggests a method; it never changes settings by itself.
enum KeyboardSetupPolicy {
  static let coreLanguages = ["yue", "en", "de"]

  static func example(for mode: ChineseInputMode) -> String {
    switch mode {
    case .phonetic: "nei5 → 你"
    case .quick: "OF · 人火 → 你"
    case .cangjie: "ONF · 人弓火 → 你"
    case .stroke: "丿丨丿乛丨… → 你"
    }
  }

  static func suggestedMethod(for response: String) -> ChineseInputMode? {
    guard response.count <= 32 else { return nil }
    let code = response.lowercased().filter { !$0.isWhitespace }
    switch code {
    case "nei", "nei5": return .phonetic
    case "of", "人火": return .quick
    case "onf", "人弓火": return .cangjie
    case ",/,n/", "丿丨丿乛丨": return .stroke
    default: return nil
    }
  }

  static func canFinishTypingTest(confirmedKeyboard: Bool, text: String) -> Bool {
    confirmedKeyboard && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
}
