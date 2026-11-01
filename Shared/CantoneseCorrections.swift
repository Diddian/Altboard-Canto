import Foundation

/// Local, deterministic corrections. They do not alter model weights or
/// require enabling automatic LLM cleanup.
struct CantoneseCorrectionRule: Codable, Equatable, Identifiable, Sendable {
  let id: UUID
  let heard: String
  let intended: String

  init(id: UUID = UUID(), heard: String, intended: String) {
    self.id = id
    self.heard = heard
    self.intended = intended
  }
}

enum CantoneseCorrections {
  static func apply(_ recognized: String, customRules: [CantoneseCorrectionRule]) -> String {
    guard !recognized.isEmpty else { return recognized }

    // Interjection "喂" addresses someone. Do not change 餵食 / 餵奶 or
    // ordinary feeding verbs: only correct an utterance-opening address.
    let range = NSRange(recognized.startIndex..., in: recognized)
    var result = greetingAtStart.stringByReplacingMatches(
      in: recognized, range: range, withTemplate: "$1$2喂"
    )
    for rule in customRules.prefix(50) {
      guard rule.heard.count >= 2, rule.heard.count <= 80,
            !rule.intended.isEmpty, rule.intended.count <= 80,
            rule.heard != rule.intended
      else { continue }
      result = result.replacingOccurrences(of: rule.heard, with: rule.intended)
    }
    return result
  }

  private static let greetingAtStart: NSRegularExpression = try! NSRegularExpression(
    pattern: #"(^|[。！？!?\n])([ \t]*)餵(?=[，,！？!?]|你(?:做乜|點呀|喺邊|聽唔聽到)|阿)"#
  )
}
