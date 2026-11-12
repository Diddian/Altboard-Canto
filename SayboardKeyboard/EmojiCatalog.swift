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

  private static let skinToneScalars = Set(0x1F3FB...0x1F3FF)

  private static func normalizedBase(_ emoji: String) -> String {
    String(String.UnicodeScalarView(
      emoji.unicodeScalars.filter { !skinToneScalars.contains(Int($0.value)) }
    ))
  }

  static let baseEntries: [EmojiCatalogEntry] = {
    entries.filter { $0.emoji == normalizedBase($0.emoji) }
  }()

  private static let variantsByBase: [String: [EmojiCatalogEntry]] = {
    Dictionary(grouping: entries) { normalizedBase($0.emoji) }
  }()

  static func skinVariants(for emoji: String) -> [EmojiCatalogEntry] {
    let variants = variantsByBase[normalizedBase(emoji)] ?? []
    guard variants.count > 1 else { return [] }
    return variants
  }

  static var preferredTone: Int {
    get {
      UserDefaults(suiteName: AppGroup.identifier)?
        .integer(forKey: "canto.emoji.skinTone.v1") ?? 0
    }
    set {
      UserDefaults(suiteName: AppGroup.identifier)?
        .set(min(5, max(0, newValue)), forKey: "canto.emoji.skinTone.v1")
    }
  }

  static func emoji(_ base: String, withTone tone: Int) -> String {
    guard tone > 0, tone <= 5 else { return normalizedBase(base) }
    let modifier = UInt32(0x1F3FA + tone)
    return skinVariants(for: base).first {
      $0.emoji.unicodeScalars.contains { $0.value == modifier }
    }?.emoji ?? normalizedBase(base)
  }

  static func selectedTone(for emoji: String) -> Int {
    for scalar in emoji.unicodeScalars {
      if (0x1F3FB...0x1F3FF).contains(Int(scalar.value)) {
        return Int(scalar.value) - 0x1F3FA
      }
    }
    return 0
  }

  static let categories = [
    "Smileys & Emotion", "People & Body", "Animals & Nature",
    "Food & Drink", "Travel & Places", "Activities", "Objects",
    "Symbols", "Flags"
  ]

  static let categorizedPages: [(group: String, emoji: [EmojiCatalogEntry])] = {
    var result = [(group: String, emoji: [EmojiCatalogEntry])]()
    for category in categories {
      let matches = baseEntries.filter { $0.group == category }
      for start in stride(from: 0, to: matches.count, by: 24) {
        result.append((group: category, emoji: Array(matches[start..<min(
          start + 24, matches.count
        )])))
      }
    }
    return result
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
      return Array(baseEntries.prefix(limit))
    }
    return Array(baseEntries.lazy.filter { entry in
      if !query.isEmpty {
        return entry.name.localizedCaseInsensitiveContains(query)
          || entry.emoji.contains(query)
      }
      return group.map { entry.group == $0 } ?? true
    }.prefix(limit))
  }

  /// One stable visible page: eight columns by three rows.
  static let recentPageSize = 24
  private static let recentKey = "canto.emoji.recent.v1"

  static func boundedRecent(_ values: [String]) -> [String] {
    Array(values.prefix(recentPageSize))
  }

  static func recent() -> [String] {
    let defaults = UserDefaults(suiteName: AppGroup.identifier)
    let saved = defaults?.stringArray(forKey: recentKey) ?? []
    let bounded = boundedRecent(saved)
    if saved.count > recentPageSize {
      // Retire old entries beyond the first page once, including existing
      // installs which previously kept two pages.
      defaults?.set(bounded, forKey: recentKey)
    }
    return saved.isEmpty ? boundedRecent(common) : bounded
  }

  static func remember(_ emoji: String) -> [String] {
    var values = recent().filter { $0 != emoji }
    values.insert(emoji, at: 0)
    let bounded = boundedRecent(values)
    UserDefaults(suiteName: AppGroup.identifier)?
      .set(bounded, forKey: recentKey)
    return bounded
  }

  private static let searchAliases: [String: String] = [
    "笑": "smile", "心": "heart", "愛": "love",
    "貓": "cat", "狗": "dog", "花": "flower",
    "食": "food", "旗": "flag", "手": "hand",
    "火": "fire", "香港": "Hong Kong"
  ]
}
