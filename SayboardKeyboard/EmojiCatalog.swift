import Foundation

/// Offline CLDR-ordered inventory generated from Unicode Emoji 18.0
/// emoji-test.txt at build time. All fully-qualified RGI sequences, including
/// flags, ZWJ families/professions and skin-tone variants, are indexed.
struct EmojiCatalogEntry: Identifiable, Sendable {
  let group: String
  let name: String
  let emoji: String
  var id: String { self.emoji }
}

enum EmojiCatalog {
  static let entries: [EmojiCatalogEntry] = {
    guard let url = Bundle.main.url(forResource: "emoji_catalog", withExtension: "tsv"),
          let contents = try? String(contentsOf: url, encoding: .utf8) else {
      return fallback
    }
    let values = contents.split(separator: "\n").dropFirst().compactMap { line -> EmojiCatalogEntry? in
      let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
      guard fields.count == 3, !fields[2].isEmpty else { return nil }
      return EmojiCatalogEntry(
        group: String(fields[0]), name: String(fields[1]), emoji: String(fields[2])
      )
    }
    return values.isEmpty ? fallback : values
  }()

  static let groups: [String] = {
    var seen = Set<String>()
    return entries.compactMap { seen.insert($0.group).inserted ? $0.group : nil }
  }()

  // Offline preview/failure fallback; production CI checks for the full TSV.
  private static let fallback: [EmojiCatalogEntry] =
    ["😀", "😃", "😂", "🥲", "❤️", "👍", "🙏", "👀", "🔥", "🌸", "🐼", "🇭🇰"]
      .map { EmojiCatalogEntry(group: "Favorites", name: $0, emoji: $0) }
}
