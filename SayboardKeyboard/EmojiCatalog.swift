import Foundation

/// One canonical Unicode RGI inventory, gated by each emoji's introduction
/// version. iOS system fonts can lag the Unicode standard used by the builder.
struct EmojiCatalogEntry: Identifiable, Sendable {
  let group: String
  let name: String
  let emoji: String
  let introduced: Double
  var id: String { emoji }
}

enum EmojiCatalog {
  /// Deliberately conservative Apple emoji compatibility, not a promise that
  /// the glyph will be available on every third-party font/device.
  static var supportedEmojiVersion: Double {
    let os = ProcessInfo.processInfo.operatingSystemVersion
    if os.majorVersion >= 27 { return 17.0 }
    if os.majorVersion >= 26 { return 16.0 }
    if os.majorVersion == 18 { return os.minorVersion >= 4 ? 16.0 : 15.1 }
    if os.majorVersion == 17 { return os.minorVersion >= 4 ? 15.1 : 15.0 }
    return 15.0
  }

  static let entries: [EmojiCatalogEntry] = {
    guard let url = Bundle.main.url(forResource: "emoji_catalog", withExtension: "tsv"),
          let contents = try? String(contentsOf: url, encoding: .utf8) else {
      return fallback
    }
    let allowed = supportedEmojiVersion
    let rows = contents.split(separator: "\n").dropFirst().compactMap { line -> EmojiCatalogEntry? in
      let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
      guard fields.count == 4 || fields.count == 3, !fields[2].isEmpty else { return nil }
      let version = fields.count == 4 ? Double(fields[3]) ?? 999 : 0.0
      guard version <= allowed else { return nil }
      return EmojiCatalogEntry(
        group: String(fields[0]), name: String(fields[1]),
        emoji: String(fields[2]), introduced: version
      )
    }
    return rows.isEmpty ? fallback : rows
  }()

  static let groups: [String] = {
    var seen = Set<String>()
    return entries.compactMap { seen.insert($0.group).inserted ? $0.group : nil }
  }()

  // Failure fallback only; CI requires the real bundled catalogue.
  private static let fallback: [EmojiCatalogEntry] =
    ["😀", "😃", "😂", "🥲", "❤️", "👍", "🙏", "👀", "🔥", "🌸", "🐼", "🇭🇰"]
      .map { EmojiCatalogEntry(group: "Smileys & Emotion", name: $0, emoji: $0, introduced: 0) }
}
