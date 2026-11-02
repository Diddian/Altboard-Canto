import Foundation
import SQLite3

struct JyutpingCandidate: Identifiable, Equatable {
  let text: String
  let romanization: String

  var id: String { self.text + "|" + self.romanization }
}

/// Read-only offline lexicon: indexed SQLite lookups, never a network request.
/// The upstream-derived lexicon is generated and bundled during the IPA build.
@MainActor
final class JyutpingDictionary {
  static let shared = JyutpingDictionary()

  private var database: OpaquePointer?
  private let defaults = UserDefaults(suiteName: AppGroup.identifier)
  private let memoryKey = "canto.jyutping.selectionCounts"
  private let schemeKey = "canto.ime.schemePreferenceCounts.v1"

  private init() {
    self.defaults?.set(false, forKey: "canto.ime.offlineDictionaryReady")
    guard let url = Bundle.main.url(forResource: "jyutping", withExtension: "sqlite3") else {
      DiagnosticLog.write("jyutping: offline dictionary resource missing")
      return
    }
    var handle: OpaquePointer?
    if sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK {
      self.database = handle
      self.defaults?.set(true, forKey: "canto.ime.offlineDictionaryReady")
    } else {
      sqlite3_close_v2(handle)
      DiagnosticLog.write("jyutping: failed to open offline dictionary")
    }
  }

  var isAvailable: Bool { self.database != nil }

  func candidates(
    for rawInput: String,
    scheme: CantoneseRomanizationScheme = .jyutping,
    limit: Int = 12
  ) -> [JyutpingCandidate] {
    let input = rawInput.lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
    guard self.database != nil, !input.isEmpty, input.count <= 48 else { return [] }
    let hasTone = input.contains(where: \.isNumber)
    let plain = input.filter(\.isLetter)
    guard !plain.isEmpty else { return [] }

    let boundedLimit = min(200, max(1, limit))
    let queryLimit = max(24, boundedLimit)
    var results: [JyutpingCandidate] = []
    var usedWords = Set<String>()
    var originRank = [String: Int]()
    func gather(_ sql: String, _ argument: String, rank: Int) {
      for candidate in self.query(sql, argument: argument, limit: queryLimit) {
        // The candidate UI shows Chinese glyphs, not romanizations: avoid
        // duplicate glyphs with different tone variants in the same list.
        if usedWords.insert(candidate.text).inserted {
          results.append(candidate)
          originRank[candidate.id] = rank
        }
      }
    }

    // Tone digits remain strict Jyutping readings. Untoned input searches
    // all three indexed spellings; the legacy scheme argument is ignored.
    _ = scheme
    if hasTone {
      gather("SELECT word,romanization FROM entries WHERE compact=? ORDER BY priority LIMIT ?", input, rank: 0)
      gather("SELECT word,romanization FROM entries WHERE compact>=? AND compact<? ORDER BY priority LIMIT ?", input, rank: 2)
    } else {
      let preferenceCounts = self.defaults?.dictionary(forKey: self.schemeKey) as? [String: Int] ?? [:]
      let preferred = CantoneseSchemePreference.preferred(preferenceCounts)
      let columns = ["plain", "yale", "sidney"].sorted {
        if $0 == preferred { return true }
        if $1 == preferred { return false }
        return false
      }
      for column in columns {
        gather("SELECT word,romanization FROM entries WHERE \(column)=? ORDER BY priority LIMIT ?", plain, rank: 0)
      }
      // A few bounded convenience aliases. Broad vowel substitutions create
      // false homophones; they do not belong in a keyboard's exact index.
      for alias in CantoneseRomanizationVariants.variants(for: plain).dropFirst().prefix(3) {
        for column in columns {
          gather("SELECT word,romanization FROM entries WHERE \(column)=? ORDER BY priority LIMIT ?", alias, rank: 1)
        }
      }
      for column in columns {
        gather(
          "SELECT word,romanization FROM entries WHERE \(column)>=? AND \(column)<? ORDER BY priority LIMIT ?",
          plain, rank: 2
        )
      }
      if plain.count >= 2 {
        gather("SELECT word,romanization FROM entries WHERE initials=? ORDER BY priority LIMIT ?", plain, rank: 3)
      }
    }
    // Exact single-character readings precede prefix phrases. Personal
    // selection counts still rank candidates within each result class.
    let counts = self.defaults?.dictionary(forKey: self.memoryKey) as? [String: Int] ?? [:]
    var ordered = results.enumerated().sorted { lhs, rhs in
      func group(_ c: JyutpingCandidate) -> Int {
        (originRank[c.id] ?? 3) * 2 + (c.text.count == 1 ? 0 : 1)
      }
      let aGroup = group(lhs.element), bGroup = group(rhs.element)
      if aGroup != bGroup { return aGroup < bGroup }
      let a = counts[lhs.element.id] ?? 0
      let b = counts[rhs.element.id] ?? 0
      if a != b { return a > b }
      return lhs.offset < rhs.offset
    }.map(\.element)

    // Keep authentic ng syllable candidates first, then optionally offer 唔
    // for users who type ng as shorthand for the canonical m4 negative.
    if !hasTone, plain == "ng",
       let negative = self.query(
         "SELECT word,romanization FROM entries WHERE plain=? AND word='唔' ORDER BY priority LIMIT ?",
         argument: "m", limit: 1
       ).first {
      ordered.removeAll { $0.text == negative.text }
      ordered.insert(negative, at: min(1, ordered.count))
    }
    return Array(ordered.prefix(boundedLimit))
  }

  /// Canonical syllable boundaries for a fully recognized spelling, used to
  /// delete only the final phonetic syllable. Prefer phrases over homophonous
  /// one-syllable entries to avoid deleting more text than requested.
  func exactRomanization(for rawInput: String) -> String? {
    let input = rawInput.lowercased()
    guard !input.isEmpty, input.count <= 48,
          input.allSatisfy({ $0.isASCII && ($0.isLetter || "123456".contains($0)) })
    else { return nil }

    let expressions: [String] = input.contains(where: \.isNumber)
      ? ["SELECT word,romanization FROM entries WHERE compact=? ORDER BY priority LIMIT ?"]
      : [
          "SELECT word,romanization FROM entries WHERE plain=? ORDER BY priority LIMIT ?",
          "SELECT word,romanization FROM entries WHERE yale=? ORDER BY priority LIMIT ?",
          "SELECT word,romanization FROM entries WHERE sidney=? ORDER BY priority LIMIT ?"
        ]
    let spellings = input.contains(where: \.isNumber)
      ? [input] : CantoneseRomanizationVariants.variants(for: input)
    let exact = spellings.flatMap { key in
      expressions.flatMap { self.query($0, argument: key, limit: 24) }
    }
    return exact.max { a, b in
      a.romanization.split(separator: " ").count < b.romanization.split(separator: " ").count
    }?.romanization
  }

  /// Exact spelling check prevents prefix-only Chinese suggestions from
  /// turning arbitrary English Backspace operations into whole-word deletes.
  func hasExactEntry(for rawInput: String) -> Bool {
    let input = rawInput.lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
    guard !input.isEmpty, input.count <= 48 else { return false }
    let sqls: [String] = input.contains(where: \.isNumber)
      ? ["SELECT word,romanization FROM entries WHERE compact=? LIMIT ?"]
      : [
          "SELECT word,romanization FROM entries WHERE plain=? LIMIT ?",
          "SELECT word,romanization FROM entries WHERE yale=? LIMIT ?",
          "SELECT word,romanization FROM entries WHERE sidney=? LIMIT ?"
        ]
    let spellings = input.contains(where: \.isNumber)
      ? [input] : CantoneseRomanizationVariants.variants(for: input)
    return spellings.contains { key in
      sqls.contains { !self.query($0, argument: key, limit: 1).isEmpty }
    }
  }

  /// Offer offline, corpus-derived words immediately after a Chinese commit.
  func continuations(after text: String, limit: Int = 9) -> [String] {
    guard !text.isEmpty else { return [] }
    let bounded = max(1, min(limit, 24))
    var words: [String] = []
    var seen = Set<String>()
    func collect(_ value: String) {
      guard !value.isEmpty, value.count <= 10, seen.insert(value).inserted else { return }
      words.append(value)
    }
    for value in Self.commonContinuations[text] ?? [] { collect(value) }
    for prefix in [text, String(text.suffix(2)), String(text.suffix(1))] {
      guard !prefix.isEmpty, words.count < bounded else { break }
      for candidate in self.query(
        "SELECT word,romanization FROM entries WHERE word>=? AND word<? ORDER BY priority LIMIT ?",
        argument: prefix, limit: 48, upperBound: prefix + "\u{10FFFF}"
      ) {
        guard candidate.text.hasPrefix(prefix), candidate.text != prefix else { continue }
        collect(String(candidate.text.dropFirst(prefix.count)))
      }
    }
    if words.count < 3 {
      for fallback in ["嘅", "都", "啦", "喎"] { collect(fallback) }
    }
    return Array(words.prefix(bounded))
  }

  private static let commonContinuations: [String: [String]] = [
    "我": ["覺得", "哋", "都", "想", "唔係"],
    "你": ["係咪", "覺得", "知唔知", "想", "哋"],
    "佢": ["哋", "係", "話", "都"],
    "今日": ["我", "有", "要", "點"],
    "聽日": ["我", "要", "再", "見"],
    "因為": ["我", "你", "佢", "呢個"],
    "所以": ["我", "你", "就", "佢"],
    "但係": ["我", "你", "佢", "都"],
    "不過": ["我", "你", "佢", "都"],
    "或者": ["我", "你", "可以", "係"],
    "根據": ["呢個", "佢", "我", "你"],
    "最": ["多", "少", "好", "緊要"],
    "真係": ["唔知", "好", "冇", "唔係"],
    "即係": ["我", "你", "話", "咁"],
    "點解": ["會", "你", "佢", "咁"],
    "可以": ["唔", "再", "一齊", "試"],
    "唔係": ["咁", "好", "我", "呢個"],
    "咁": ["樣", "難", "好", "多"],
    "冇": ["問題", "咩", "嘢", "所謂"]
  ]

  func remember(_ candidate: JyutpingCandidate, typed: String? = nil) {
    if let typed,
       let scheme = CantoneseSchemePreference.inferredScheme(
         input: typed, canonical: candidate.romanization
       ) {
      var counts = self.defaults?.dictionary(forKey: self.schemeKey) as? [String: Int] ?? [:]
      // Gradual aging prevents long-term preference from locking forever.
      if counts.values.reduce(0, +) >= 120 {
        for key in CantoneseSchemePreference.keys {
          counts[key] = (counts[key] ?? 0) / 2
        }
      }
      counts[scheme] = min(120, (counts[scheme] ?? 0) + 1)
      self.defaults?.set(counts, forKey: self.schemeKey)
    }
    var counts = self.defaults?.dictionary(forKey: self.memoryKey) as? [String: Int] ?? [:]
    counts[candidate.id] = min(10000, (counts[candidate.id] ?? 0) + 1)
    if counts.count > 1000 {
      counts = Dictionary(uniqueKeysWithValues:
        counts.sorted { $0.value > $1.value }.prefix(600).map { ($0.key, $0.value) })
    }
    self.defaults?.set(counts, forKey: self.memoryKey)
  }

  private func query(
    _ sql: String, argument: String, limit: Int, upperBound: String? = nil
  ) -> [JyutpingCandidate] {
    guard let database = self.database else { return [] }
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
      sqlite3_finalize(statement)
      return []
    }
    defer { sqlite3_finalize(statement) }
    let destructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    let paramCount = sqlite3_bind_parameter_count(statement)
    _ = argument.withCString { pointer in
      sqlite3_bind_text(statement, 1, pointer, -1, destructor)
    }
    if paramCount == 3 {
      _ = (upperBound ?? (argument + "{")).withCString { pointer in
        sqlite3_bind_text(statement, 2, pointer, -1, destructor)
      }
    }
    sqlite3_bind_int(statement, paramCount, Int32(limit))
    var found = [JyutpingCandidate]()
    while sqlite3_step(statement) == SQLITE_ROW {
      guard let word = sqlite3_column_text(statement, 0),
            let romanization = sqlite3_column_text(statement, 1) else { continue }
      found.append(JyutpingCandidate(text: String(cString: word), romanization: String(cString: romanization)))
    }
    return found
  }
}
