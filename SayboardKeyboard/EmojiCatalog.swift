import Foundation

struct EmojiCatalogEntry: Identifiable, Sendable {
  let group: String
  let name: String
  let emoji: String
  var id: String { self.emoji }
}

/// Bundled Unicode RGI Emoji sequences, never a request to an online service.
/// A small common set remains usable if the generated resource is unavailable.
enum EmojiCatalog {
  static let entries: [EmojiCatalogEntry] = {
    guard let url = Bundle.main.url(forResource: "emoji_catalog", withExtension: "tsv"),
          let contents = try? String(contentsOf: url, encoding: .utf8) else {
      return fallback
    }
    let values = contents.split(separator: "\n").dropFirst().compactMap {
      line -> EmojiCatalogEntry? in
      let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
      guard fields.count == 3, !fields[2].isEmpty else { return nil }
      return EmojiCatalogEntry(
        group: String(fields[0]),
        name: String(fields[1]),
        emoji: String(fields[2])
      )
    }
    return values.isEmpty ? fallback : values
  }()

  static let common = [
    "😂", "🫣", "😨", "😭", "😏", "🤤", "😊", "😜",
    "🫡", "😆", "💔", "🥺", "🤷", "😌", "🤪", "🥹",
    "😱", "😮‍💨", "😩", "😠", "👺", "👊", "🥸", "😴",
    "🥴", "🖤", "👀", "☺️", "😅", "✔️", "🤫", "😔"
  ]

  private static let fallback = common.map {
    EmojiCatalogEntry(group: "Smileys & Emotion", name: $0, emoji: $0)
  }

  static func search(_ text: String, group: String?, limit: Int = 700)
    -> [EmojiCatalogEntry] {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let query = searchAliases[trimmed] ?? trimmed
    guard !query.isEmpty || group != nil else {
      return Array(entries.prefix(limit))
    }
    return Array(entries.lazy.filter { entry in
      if !query.isEmpty {
        return entry.name.localizedCaseInsensitiveContains(query)
          || entry.emoji.contains(query)
      }
      return group.map { entry.group == $0 } ?? true
    }.prefix(limit))
  }

  static func recent() -> [String] {
    let saved = UserDefaults(suiteName: AppGroup.identifier)?
      .stringArray(forKey: "canto.emoji.recent.v1") ?? []
    return saved.isEmpty ? common : saved
  }

  static func remember(_ emoji: String) -> [String] {
    var values = recent().filter { $0 != emoji }
    values.insert(emoji, at: 0)
    let recent = Array(values.prefix(48))
    UserDefaults(suiteName: AppGroup.identifier)?
      .set(recent, forKey: "canto.emoji.recent.v1")
    return recent
  }

  private static let searchAliases: [String: String] = [
    "笑": "smile", "心": "heart", "愛": "love",
    "貓": "cat", "狗": "dog", "花": "flower",
    "食": "food", "旗": "flag", "手": "hand",
    "火": "fire", "香港": "Hong Kong"
  ]
}
