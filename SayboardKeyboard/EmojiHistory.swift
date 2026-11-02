import Foundation

/// Local aggregate emoji usage; no host text, raw keystrokes, or network access.
enum EmojiHistory {
  private static let countsKey = "altboard.emoji.usageCounts.v1"
  private static let recencyKey = "altboard.emoji.recentOrder.v1"
  private static let maximumRecords = 96

  static func mostUsed(available: [EmojiCatalogEntry] = EmojiCatalog.entries) -> [EmojiCatalogEntry] {
    let defaults = AppGroup.sharedDefaults ?? .standard
    let counts = defaults.dictionary(forKey: countsKey) as? [String: Int] ?? [:]
    let recency = defaults.stringArray(forKey: recencyKey) ?? []
    let order = Dictionary(uniqueKeysWithValues: recency.enumerated().map { ($0.element, $0.offset) })
    return available.filter { (counts[$0.emoji] ?? 0) > 0 }
      .sorted { lhs, rhs in
        let a = counts[lhs.emoji] ?? 0, b = counts[rhs.emoji] ?? 0
        return a == b ? (order[lhs.emoji] ?? Int.max) < (order[rhs.emoji] ?? Int.max) : a > b
      }
      .prefix(maximumRecords)
      .map { $0 }
  }

  static func remember(_ emoji: String) {
    let defaults = AppGroup.sharedDefaults ?? .standard
    var recency = defaults.stringArray(forKey: recencyKey) ?? []
    recency.removeAll { $0 == emoji }
    recency.insert(emoji, at: 0)
    if recency.count > maximumRecords { recency = Array(recency.prefix(maximumRecords)) }
    var counts = defaults.dictionary(forKey: countsKey) as? [String: Int] ?? [:]
    counts[emoji] = min(10_000, (counts[emoji] ?? 0) + 1)
    // Only retain entries present in the bounded recency window.
    let known = Set(recency)
    counts = counts.filter { known.contains($0.key) }
    defaults.set(recency, forKey: recencyKey)
    defaults.set(counts, forKey: countsKey)
  }
}
