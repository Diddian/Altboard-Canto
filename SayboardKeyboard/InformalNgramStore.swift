import Foundation
import SQLite3

/// Read-only editorial seed vocabulary and contextual suggestions.
/// The database also holds observed HKCanCor counts, in separate tables.
@MainActor
final class InformalNgramStore {
  static let shared = InformalNgramStore()
  private var database: OpaquePointer?

  init(databaseURL: URL? = Bundle.main.url(forResource: "jyutping", withExtension: "sqlite3")) {
    guard let databaseURL else { return }
    var handle: OpaquePointer?
    if sqlite3_open_v2(databaseURL.path, &handle,
                       SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK {
      self.database = handle
    } else {
      sqlite3_close_v2(handle)
    }
  }

  isolated deinit {
    if let database { sqlite3_close_v2(database) }
  }

  private func languages(_ preferred: [String]) -> [String] {
    var codes = LatinWordSuggestionPolicy.preferredCodes(preferred)
      .filter { $0 == "en" || $0 == "de" }
    if preferred.contains(where: { $0.lowercased().hasPrefix("yue") }) {
      codes.append("yue")
    }
    return codes
  }

  /// Each statement uses an indexed prefix or exact-match query and a hard cap.
  private func rows(_ sql: String, values: [String], limit: Int = 32) -> [(String, Int)] {
    guard let database else { return [] }
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
      sqlite3_finalize(statement)
      return []
    }
    defer { sqlite3_finalize(statement) }
    let destructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    for (index, value) in values.enumerated() {
      _ = value.withCString {
        sqlite3_bind_text(statement, Int32(index + 1), $0, -1, destructor)
      }
    }
    sqlite3_bind_int(statement, Int32(values.count + 1), Int32(min(50, max(1, limit))))
    var found = [(String, Int)]()
    while sqlite3_step(statement) == SQLITE_ROW {
      guard let pointer = sqlite3_column_text(statement, 0) else { continue }
      found.append((String(cString: pointer), Int(sqlite3_column_int(statement, 1))))
    }
    return found
  }

  func hasTerm(_ word: String, preferred: [String]) -> Bool {
    let key = word.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
    guard (2...32).contains(key.count) else { return false }
    for language in languages(preferred) {
      if !rows("SELECT key,1 FROM informal_terms WHERE language=? AND key=? LIMIT ?",
               values: [language, key], limit: 1).isEmpty {
        return true
      }
    }
    return false
  }

  func completions(for typed: String, preferred: [String], limit: Int = 12)
    -> [LatinWordSuggestion] {
    let key = typed.lowercased()
    guard (2...32).contains(key.count) else { return [] }
    var suggestions = [LatinWordSuggestion]()
    for language in languages(preferred) {
      for (display, _) in rows(
        "SELECT display,0 FROM informal_terms WHERE language=? AND key>=? AND key<? "
          + "ORDER BY key LIMIT ?",
        values: [language, key, key + "\u{10FFFF}"], limit: limit
      ) {
        guard display.lowercased() != key else { continue }
        suggestions.append(LatinWordSuggestion(
          text: LatinWordSuggestionPolicy.matchCapitalization(display, typed: typed),
          language: language
        ))
        if suggestions.count >= limit { return suggestions }
      }
    }
    return suggestions
  }

  /// Editorial context weights are only a bounded tie-breaker, not a model of
  /// real conversational frequencies. No raw host text is stored or uploaded.
  func contextWeights(context: String?, current: String?, preferred: [String]) -> [String: Int] {
    let tokens = InformalNgramPolicy.preceding(in: context, current: current)
    let histories = InformalNgramPolicy.histories(for: tokens)
    guard !histories.isEmpty else { return [:] }
    var weights = [String: Int]()
    for language in languages(preferred) {
      for (index, history) in histories.enumerated() {
        for (token, weight) in rows(
          "SELECT token,seed_weight FROM informal_ngrams WHERE language=? AND history=? "
            + "ORDER BY seed_weight DESC,token LIMIT ?",
          values: [language, history], limit: 32
        ) {
          let key = language + "|" + token
          weights[key] = max(weights[key] ?? 0, min(18, weight * (index == 0 ? 3 : 1)))
        }
      }
    }
    return weights
  }

  func nextWords(after context: String?, preferred: [String], limit: Int = 6)
    -> [LatinWordSuggestion] {
    guard let context, context.last?.isWhitespace == true else { return [] }
    let weights = contextWeights(context: context, current: nil, preferred: preferred)
    let languages = self.languages(preferred)
    let ranked = weights.map { key, weight -> (LatinWordSuggestion, Int)? in
      guard let divider = key.firstIndex(of: "|") else { return nil }
      let language = String(key[..<divider])
      let word = String(key[key.index(after: divider)...])
      guard languages.contains(language), (2...32).contains(word.count),
            word.first?.isLetter == true else { return nil }
      return (LatinWordSuggestion(text: word, language: language), weight)
    }.compactMap { $0 }
    return Array(ranked.sorted { left, right in
      if left.1 != right.1 { return left.1 > right.1 }
      let a = languages.firstIndex(of: left.0.language) ?? 99
      let b = languages.firstIndex(of: right.0.language) ?? 99
      return a == b ? left.0.text < right.0.text : a < b
    }.prefix(max(1, min(limit, 9))).map(\.0))
  }
}
