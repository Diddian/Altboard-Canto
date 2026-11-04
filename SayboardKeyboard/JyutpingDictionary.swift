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
  private let memoryKey = CantoneseSchemePreference.candidateStorageKey
  private let schemeKey = CantoneseSchemePreference.preferenceStorageKey

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
    guard self.database != nil, !input.isEmpty, input.count <= 96 else { return [] }
    let hasTone = input.contains(where: \.isNumber)
    let plain = input.filter(\.isLetter)
    guard !plain.isEmpty else { return [] }

    let boundedLimit = min(200, max(1, limit))
    // Fixed lookup depth keeps the first compact candidates identical to
    // the expanded grid while avoiding 200-row lookups on every keystroke.
    let queryLimit = 72
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
      let columns = CantoneseSchemePreference.lookupOrder(preferenceCounts)
      for column in columns {
        gather("SELECT word,romanization FROM entries WHERE \(column)=? ORDER BY priority LIMIT ?", plain, rank: 0)
      }
      // Curated multi-syllable combinations of Jyutping/Yale/Sidney Lau.
      // The indexed table covers only reviewed colloquial phrases.
      gather(
        "SELECT word,romanization FROM mixed_aliases WHERE alias=? ORDER BY priority LIMIT ?",
        plain, rank: 1
      )
      // A few bounded convenience aliases. Broad vowel substitutions create
      // false homophones; they do not belong in a keyboard's exact index.
      for alias in CantoneseRomanizationVariants.variants(for: plain).dropFirst().prefix(3) {
        for column in columns {
          gather("SELECT word,romanization FROM entries WHERE \(column)=? ORDER BY priority LIMIT ?", alias, rank: 1)
        }
        gather(
          "SELECT word,romanization FROM mixed_aliases WHERE alias=? ORDER BY priority LIMIT ?",
          alias, rank: 1
        )
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
    // Compose a short sequence of complete words when no whole-phrase reading
    // exists. No large synthetic phrase table or raw keystroke history needed.
    if !hasTone, !results.contains(where: { (originRank[$0.id] ?? 3) <= 1 }) {
      if let repeated = self.repeatedNegationCandidate(for: plain),
         usedWords.insert(repeated.text).inserted {
        results.insert(repeated, at: 0)
        originRank[repeated.id] = 1
      } else if let combined = self.composedCandidate(for: plain),
                usedWords.insert(combined.text).inserted {
        results.insert(combined, at: 0)
        originRank[combined.id] = -1
      }
    }

    // An entered syllable yields characters, two complete syllables words,
    // and three or more can yield phrases. Do not flood a single-character
    // search with every nine-character phrase sharing its prefix.
    let exactSyllables = results.filter { (originRank[$0.id] ?? 3) <= 1 }
      .map { $0.romanization.split(separator: " ").count }.max() ?? 0
    let maximum: Int
    if exactSyllables > 0 {
      maximum = exactSyllables < 3 ? exactSyllables : exactSyllables + 1
    } else {
      maximum = plain.count <= 4 ? 1 : min(6, max(2, plain.count / 3 + 1))
    }
    results.removeAll {
      (originRank[$0.id] ?? 3) >= 2 && $0.text.count > maximum
    }

    // A short spelling such as "ga" may have many single-character matches,
    // but the first 24 prefix rows can be occupied by longer phrases that
    // the length filter above removes. Backfill only when the compact strip
    // lacks candidates, filtering by word length *before* SQL LIMIT.
    // Expanded candidates keep their existing broader search behavior.
    if !hasTone, (2...4).contains(plain.count), maximum >= 1,
       results.count < 24 {
      let preferences = self.defaults?.dictionary(forKey: self.schemeKey) as? [String: Int] ?? [:]
      for column in CantoneseSchemePreference.lookupOrder(preferences) {
        gather(
          "SELECT word,romanization FROM entries WHERE \(column)>=? AND \(column)<? AND length(word)=1 ORDER BY priority LIMIT ?",
          plain, rank: 2
        )
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
      let preferences = self.defaults?.dictionary(forKey: self.schemeKey) as? [String: Int] ?? [:]
      let promote = CantoneseSchemePreference.prefersColloquialNg(preferences)
      ordered.insert(negative, at: min(promote ? 0 : 1, ordered.count))
    }
    return Array(ordered.prefix(boundedLimit))
  }

  /// Canonical syllable boundaries for a fully recognized spelling, used to
  /// delete only the final phonetic syllable. Prefer phrases over homophonous
  /// one-syllable entries to avoid deleting more text than requested.
  func exactRomanization(for rawInput: String) -> String? {
    let input = rawInput.lowercased()
    guard !input.isEmpty, input.count <= 96,
          input.allSatisfy({ $0.isASCII && ($0.isLetter || "123456".contains($0)) })
    else { return nil }

    let expressions: [String] = input.contains(where: \.isNumber)
      ? ["SELECT word,romanization FROM entries WHERE compact=? ORDER BY priority LIMIT ?"]
      : [
          "SELECT word,romanization FROM entries WHERE plain=? ORDER BY priority LIMIT ?",
          "SELECT word,romanization FROM entries WHERE yale=? ORDER BY priority LIMIT ?",
          "SELECT word,romanization FROM entries WHERE sidney=? ORDER BY priority LIMIT ?",
          "SELECT word,romanization FROM mixed_aliases WHERE alias=? ORDER BY priority LIMIT ?"
        ]
    let spellings = input.contains(where: \.isNumber)
      ? [input] : CantoneseRomanizationVariants.variants(for: input)
    let exact = spellings.flatMap { key in
      expressions.flatMap { self.query($0, argument: key, limit: 24) }
    }
    let found = exact.max { a, b in
      a.romanization.split(separator: " ").count < b.romanization.split(separator: " ").count
    }?.romanization
    return found ?? (input.contains(where: \.isNumber) ? nil
      : (self.repeatedNegationCandidate(for: input)
         ?? self.composedCandidate(for: input))?.romanization)
  }

  /// Exact spelling check prevents prefix-only Chinese suggestions from
  /// turning arbitrary English Backspace operations into whole-word deletes.
  func hasExactEntry(for rawInput: String) -> Bool {
    let input = rawInput.lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
    guard !input.isEmpty, input.count <= 96 else { return false }
    let sqls: [String] = input.contains(where: \.isNumber)
      ? ["SELECT word,romanization FROM entries WHERE compact=? LIMIT ?"]
      : [
          "SELECT word,romanization FROM entries WHERE plain=? LIMIT ?",
          "SELECT word,romanization FROM entries WHERE yale=? LIMIT ?",
          "SELECT word,romanization FROM entries WHERE sidney=? LIMIT ?",
          "SELECT word,romanization FROM mixed_aliases WHERE alias=? LIMIT ?"
        ]
    let spellings = input.contains(where: \.isNumber)
      ? [input] : CantoneseRomanizationVariants.variants(for: input)
    if spellings.contains(where: { key in
      sqls.contains { !self.query($0, argument: key, limit: 1).isEmpty }
    }) { return true }
    return !input.contains(where: \.isNumber)
      && (self.repeatedNegationCandidate(for: input) != nil
          || self.composedCandidate(for: input, maxChunks: 3) != nil)
  }

  /// Form A唔A from a verified single-character predicate, without
  /// storing arbitrary generated phrases or treating every ng as negative.
  private func repeatedNegationCandidate(for spelling: String) -> JyutpingCandidate? {
    guard let base = CantoneseRomanizationVariants.repeatedNegationBase(for: spelling),
          (2...12).contains(base.count) else { return nil }
    let predicates: Set<String> = [
      "會", "食", "做", "去", "係", "有", "好", "得", "要", "知", "識",
      "飲", "買", "睇", "聽", "講", "走", "嚟", "行", "返", "坐",
      "瞓", "搵", "愛", "憎", "怕", "慣", "開", "閂", "試", "用",
      "打", "答", "等", "記", "信", "覺", "教", "學", "玩", "跳",
      "笑", "寫", "讀", "唱", "飛", "跟", "忍", "放", "醒",
      "肯", "明", "見", "似", "諗"
    ]
    let preferences = self.defaults?.dictionary(forKey: self.schemeKey) as? [String: Int] ?? [:]
    let columns = CantoneseSchemePreference.lookupOrder(preferences)
    for alias in CantoneseRomanizationVariants.variants(for: base) {
      for column in columns {
        let matches = self.query(
          "SELECT word,romanization FROM entries WHERE \(column)=? ORDER BY priority LIMIT ?",
          argument: alias, limit: 24
        )
        if let verb = matches.first(where: { $0.text.count == 1 && predicates.contains($0.text) }) {
          return JyutpingCandidate(
            text: verb.text + "唔" + verb.text,
            romanization: verb.romanization + " m4 " + verb.romanization
          )
        }
      }
    }
    return nil
  }

  /// Use complete indexed words to assemble longer unspaced utterances.
  /// Only two/three-chunk forms qualify for automatic Space commitment.
  /// Longer forms remain explicit candidates until confirmed by the user.
  private func composedCandidate(
    for spelling: String, maxChunks: Int = 8
  ) -> JyutpingCandidate? {
    guard (7...52).contains(spelling.count),
          spelling.allSatisfy({ $0.isASCII && $0.isLetter }) else { return nil }
    let letters = Array(spelling)
    let preferences = self.defaults?.dictionary(forKey: self.schemeKey) as? [String: Int] ?? [:]
    let columns = CantoneseSchemePreference.lookupOrder(preferences)
    var hits = [String: JyutpingCandidate]()
    var misses = Set<String>()
    func exact(_ range: Range<Int>) -> JyutpingCandidate? {
      let code = String(letters[range])
      if let value = hits[code] { return value }
      if misses.contains(code) { return nil }
      for variant in CantoneseRomanizationVariants.variants(for: code) {
        for column in columns {
          if let value = self.query(
            "SELECT word,romanization FROM entries WHERE \(column)=? ORDER BY priority LIMIT ?",
            argument: variant, limit: 1
          ).first {
            hits[code] = value
            return value
          }
        }
        if let value = self.query(
          "SELECT word,romanization FROM mixed_aliases WHERE alias=? ORDER BY priority LIMIT ?",
          argument: variant, limit: 1
        ).first {
          hits[code] = value
          return value
        }
      }
      misses.insert(code)
      return nil
    }
    func join(_ parts: [JyutpingCandidate]) -> JyutpingCandidate {
      JyutpingCandidate(
        text: parts.map(\.text).joined(),
        romanization: parts.map(\.romanization).joined(separator: " ")
      )
    }
    let final = letters.count
    // Prefer a complete two-word split; it is less ambiguous than three.
    for split in 2...min(14, final - 2) {
      guard let first = exact(0..<split), first.text.count <= 4,
            let second = exact(split..<final), second.text.count <= 5
      else { continue }
      return join([first, second])
    }
    // A three-word composition also handles 其實 + 我 + 係.
    if final <= 28 {
      for a in 2...min(12, final - 4) {
        guard let first = exact(0..<a), first.text.count <= 4 else { continue }
        for b in (a + 2)...min(a + 12, final - 2) {
          guard let middle = exact(a..<b), middle.text.count <= 4,
                let last = exact(b..<final), last.text.count <= 4
          else { continue }
          return join([first, middle, last])
        }
      }
    }
    guard maxChunks > 3, final <= 52 else { return nil }

    // Bounded dynamic segmentation from verified lexicon entries. Favor
    // fewer, longer matched words; never invent phonetic substitutions.
    // Memoize substring results and cap SQLite probes during one refresh.
    var paths = Array<[JyutpingCandidate]?>(repeating: nil, count: final + 1)
    paths[0] = []
    var probes = 0
    for start in 0..<final {
      guard let prefix = paths[start], prefix.count < maxChunks else { continue }
      let upper = min(14, final - start)
      guard upper >= 2 else { continue }
      for length in stride(from: upper, through: 2, by: -1) {
        if probes >= 84 { break }
        probes += 1
        let finish = start + length
        guard let next = exact(start..<finish),
              next.text.count <= 5 else { continue }
        let proposed = prefix + [next]
        if paths[finish] == nil || proposed.count < paths[finish]!.count {
          paths[finish] = proposed
        }
      }
    }
    guard let chunks = paths[final], (4...maxChunks).contains(chunks.count)
    else { return nil }
    return join(chunks)
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
    "我": ["覺得", "哋", "都", "想", "唔係", "今日", "有", "冇", "會", "可以", "知", "想問"],
    "你": ["係咪", "覺得", "知唔知", "想", "哋", "有", "冇", "會", "可以", "今日"],
    "妳": ["係", "想", "有", "冇", "會", "哋"],
    "佢": ["哋", "係", "話", "都", "有", "冇", "想", "會", "可以", "覺得"],
    "她": ["係", "哋", "話", "有", "冇", "都"],
    "他": ["係", "哋", "話", "有", "冇", "都"],
    "它": ["係", "會", "都"],
    "這": ["個", "啲", "樣", "邊"],
    "呢": ["個", "啲", "度", "邊", "樣"],
    "嗰": ["個", "啲", "度", "邊", "樣"],
    "哪": ["個", "裏", "裡", "兒"],
    "那": ["個", "裏", "裡", "邊", "時"],
    "拿": ["起", "住"],
    "嗱": ["嗱聲"],
    "咁": ["樣", "就", "咪", "即係", "其實", "你", "我", "佢"],
    "噉": ["樣", "就", "咪"],
    "即": ["係", "係話", "刻", "時", "使"],
    "啫": ["係", "係話"],
    "就": ["係", "算", "咁"],
    "點": ["解", "樣", "算", "知", "先"],
    "邊": ["個", "啲", "度"],
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
    "唔係": ["呀嘛", "呀", "喎", "咁", "好", "我", "呢個"],
    "咁": ["樣", "難", "好", "多"],
    "冇": ["問題", "咩", "嘢", "所謂"]
  ]

  func remember(_ candidate: JyutpingCandidate, typed: String? = nil) {
    if let typed {
      let counts = self.defaults?.dictionary(forKey: self.schemeKey) as? [String: Int] ?? [:]
      let updated = CantoneseSchemePreference.recordingSelection(
        in: counts, typed: typed, canonical: candidate.romanization
      )
      if updated != counts {
        self.defaults?.set(updated, forKey: self.schemeKey)
      }
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
