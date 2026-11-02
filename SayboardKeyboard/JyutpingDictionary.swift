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

    // Tone-digit input must honor tones, not silently ignore them.
    if hasTone {
      gather("SELECT word,romanization FROM entries WHERE compact=? ORDER BY priority LIMIT ?", input, rank: 0)
      gather("SELECT word,romanization FROM entries WHERE compact>=? AND compact<? ORDER BY priority LIMIT ?", input, rank: 2)
    } else {
      // Candidate aliases cover both systems, with selected scheme first.
      if scheme == .yale {
        gather("SELECT word,romanization FROM entries WHERE yale=? ORDER BY priority LIMIT ?", plain, rank: 0)
      }
      gather("SELECT word,romanization FROM entries WHERE plain=? ORDER BY priority LIMIT ?", plain, rank: 0)
      if scheme != .yale {
        gather("SELECT word,romanization FROM entries WHERE yale=? ORDER BY priority LIMIT ?", plain, rank: 0)
      }
      if scheme == .yale {
        gather("SELECT word,romanization FROM entries WHERE yale>=? AND yale<? ORDER BY priority LIMIT ?", plain, rank: 2)
      }
      gather("SELECT word,romanization FROM entries WHERE plain>=? AND plain<? ORDER BY priority LIMIT ?", plain, rank: 2)
      if scheme != .yale {
        gather("SELECT word,romanization FROM entries WHERE yale>=? AND yale<? ORDER BY priority LIMIT ?", plain, rank: 2)
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

    // A convenience spelling for users who enter "ng" for the negative
    // 唔. Its dictionary reading remains m4, not a fabricated ng reading.
    // Leave the genuine ng candidates first and place 唔 immediately after.
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
          "SELECT word,romanization FROM entries WHERE yale=? ORDER BY priority LIMIT ?"
        ]
    let exact = expressions.flatMap { self.query($0, argument: input, limit: 24) }
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
          "SELECT word,romanization FROM entries WHERE yale=? LIMIT ?"
        ]
    return sqls.contains { !self.query($0, argument: input, limit: 1).isEmpty }
  }

  func remember(_ candidate: JyutpingCandidate) {
    var counts = self.defaults?.dictionary(forKey: self.memoryKey) as? [String: Int] ?? [:]
    counts[candidate.id] = min(10000, (counts[candidate.id] ?? 0) + 1)
    if counts.count > 1000 {
      counts = Dictionary(uniqueKeysWithValues:
        counts.sorted { $0.value > $1.value }.prefix(600).map { ($0.key, $0.value) })
    }
    self.defaults?.set(counts, forKey: self.memoryKey)
  }

  private func query(_ sql: String, argument: String, limit: Int) -> [JyutpingCandidate] {
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
      _ = (argument + "{").withCString { pointer in
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
