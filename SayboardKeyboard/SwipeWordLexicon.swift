import Foundation

/// Offline English frequency dictionary adapted from the lexical strategy of
/// JBoard (MIT implementation; corpus notices bundled separately). The word
/// list is staged at build time and used locally, never fetched on the phone.
@MainActor
final class SwipeWordLexicon {
  static let shared = SwipeWordLexicon()

  private struct Entry {
    let word: String
    let frequency: Int64
  }

  private let endpoints: [String: [Entry]]
  private let sorted: [Entry]

  private init() {
    var entries = [Entry]()
    if let url = Bundle.main.url(forResource: "english-frequency", withExtension: "txt"),
       let text = try? String(contentsOf: url, encoding: .utf8) {
      for line in text.split(whereSeparator: \.isNewline) {
        let fields = line.split(whereSeparator: \.isWhitespace)
        guard fields.count == 2, let frequency = Int64(fields[1]), frequency > 0 else { continue }
        let word = String(fields[0]).lowercased()
          .replacingOccurrences(of: "\u{feff}", with: "")
        guard (2...32).contains(word.count),
              word.utf8.allSatisfy({ (97...122).contains($0) }) else { continue }
        entries.append(Entry(word: word, frequency: frequency))
      }
    }
    self.sorted = entries.sorted { $0.word < $1.word }
    self.endpoints = Dictionary(grouping: entries) { entry in
      String(entry.word.first!) + String(entry.word.last!)
    }
  }

  var wordCount: Int { self.sorted.count }

  /// A bounded lexical prefix lookup for the suggestion bar.
  func prefixMatches(_ prefix: String, limit: Int = 10) -> [String] {
    let query = prefix.lowercased()
    guard (3...32).contains(query.count), limit > 0 else { return [] }
    var low = 0, high = self.sorted.count
    while low < high {
      let middle = (low + high) / 2
      if self.sorted[middle].word < query { low = middle + 1 }
      else { high = middle }
    }
    var matches = [Entry]()
    var index = low
    while index < self.sorted.count && self.sorted[index].word.hasPrefix(query) {
      if self.sorted[index].word != query { matches.append(self.sorted[index]) }
      index += 1
    }
    return matches.sorted { $0.frequency > $1.frequency }.prefix(limit).map(\.word)
  }

  /// Endpoint buckets avoid scanning 82k entries during every swipe. Near
  /// neighbors tolerate small finger start/end offsets; geometry is ranked
  /// by LatinSwipeDecoder after this frequency-ranked candidate retrieval.
  func nearbyWords(path: [LatinSwipePoint], arrangement: LetterKeyArrangement,
                   fullWidth: Double, limit: Int = 2500) -> [String] {
    guard let first = path.first, let last = path.last else { return [] }
    let centers = LatinSwipeDecoder.centers(arrangement: arrangement, fullWidth: fullWidth)
    func nearest(_ point: LatinSwipePoint) -> [String] {
      centers.map { ($0.key, $0.value.distance(to: point)) }
        .filter { $0.1 <= 88 }
        .sorted { $0.1 < $1.1 }
        .prefix(4)
        .map(\.0)
    }
    let starts = nearest(first), ends = nearest(last)
    guard !starts.isEmpty, !ends.isEmpty else { return [] }
    var hits = [Entry]()
    for a in starts {
      for b in ends { hits.append(contentsOf: self.endpoints[a + b] ?? []) }
    }
    return hits.sorted { $0.frequency > $1.frequency }
      .prefix(max(1, limit)).map(\.word)
  }
}
