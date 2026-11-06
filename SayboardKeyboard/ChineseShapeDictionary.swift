import Foundation
import SQLite3
import CoreText

struct ChineseShapeCandidate: Identifiable, Equatable {
  let text: String
  let code: String
  let mode: ChineseInputMode
  let variant: Int
  let ambiguousVariant: Bool

  var id: String { "\(mode.rawValue)|\(code)|\(text)|\(variant)" }
}

/// Read-only fused Fcitx5/Rime table with bounded explicit-choice ranking.
/// One SQLite connection, no Rime runtime, no network, no raw host typing logs.
@MainActor
final class ChineseShapeDictionary {
  static let shared = ChineseShapeDictionary()

  private var database: OpaquePointer?
  private let defaults = UserDefaults(suiteName: AppGroup.identifier)
  private let generationKey = "canto.ime.shapeGenerationCounts.v1"
  private let wordKey = "canto.ime.shapeWordCounts.v1"
  private let strokePrefixKey = "canto.ime.strokePrefixSelections.v1"

  private init() {
    guard let url = Bundle.main.url(forResource: "chinese-shapes", withExtension: "sqlite3")
    else { return }
    var db: OpaquePointer?
    guard sqlite3_open_v2(url.path, &db,
                          SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK
    else {
      sqlite3_close_v2(db)
      return
    }
    self.database = db
  }

  var isAvailable: Bool { self.database != nil }

  func candidates(for raw: String, mode: ChineseInputMode, limit: Int = 12)
    -> [ChineseShapeCandidate] {
    guard mode.usesShapeTable, self.database != nil,
          let code = self.normalized(raw, mode: mode) else { return [] }
    let generationCounts = self.defaults?.dictionary(forKey: self.generationKey)
      as? [String: Int] ?? [:]
    let preferred = ChineseShapeRanking.preferredVariant(generationCounts, mode: mode)
    let wordCounts = self.defaults?.dictionary(forKey: self.wordKey)
      as? [String: Int] ?? [:]
    let strokeCounts = mode == .stroke
      ? (self.defaults?.dictionary(forKey: self.strokePrefixKey) as? [String: Int] ?? [:])
      : [:]
    let confirmedChinese = ConfirmedChoiceLearning.chineseCounts(defaults: self.defaults)
    let maxLimit = max(1, min(200, limit))
    // A bounded prefix lookup is only used when there are few exact matches.
    let exact = self.fetch(mode: mode, code: code, prefix: false, limit: 300)
    let prefix = exact.count < maxLimit
      ? self.fetch(mode: mode, code: code, prefix: true,
                   limit: min(240, max(120, maxLimit))) : []
    var best: [String: (candidate: ChineseShapeCandidate, score: Int)] = [:]
    var matchedVariants: [String: Set<Int>] = [:]

    // A prefix can match both generations even when its exact code cannot.
    // Only unambiguous explicit selections should influence generation bias.
    for hit in exact + prefix {
      matchedVariants[hit.word, default: []].insert(hit.variant)
    }
    for (isExact, hits) in [(true, exact), (false, prefix)] {
      for hit in hits {
        let count = wordCounts[mode.rawValue + "|" + hit.word] ?? 0
        let score = ChineseShapeRanking.score(
          priority: hit.priority, variant: hit.variant, preferred: preferred,
          count: count, exact: isExact,
          sharedCount: ConfirmedChoiceLearning.chinesePreference(
            hit.word, counts: confirmedChinese
          )
        ) - (mode == .stroke
          ? ChineseShapeRanking.strokeChoiceBonus(
              strokeCounts[code + "|" + hit.word] ?? 0
            ) : 0)
        let candidate = ChineseShapeCandidate(
          text: hit.word, code: hit.code, mode: mode, variant: hit.variant,
          ambiguousVariant: (matchedVariants[hit.word]?.count ?? 0) > 1
        )
        if let current = best[hit.word], current.score <= score { continue }
        best[hit.word] = (candidate, score)
      }
    }
    // Never propose a missing-font square or replacement character on iOS.
    // Keep its source record intact, but omit it from visible candidates.
    return Array(best.values.filter { Self.canDisplay($0.candidate.text) }.sorted {
      if $0.score != $1.score { return $0.score < $1.score }
      return $0.candidate.text < $1.candidate.text
    }.prefix(maxLimit).map { $0.candidate })
  }

  func remember(_ candidate: ChineseShapeCandidate, typedCode: String) {
    guard candidate.mode.usesShapeTable else { return }
    let word = candidate.mode.rawValue + "|" + candidate.text
    let counts = self.defaults?.dictionary(forKey: self.wordKey)
      as? [String: Int] ?? [:]
    self.defaults?.set(
      ConfirmedChoiceLearning.increment(
        word, in: counts, maximum: 160, trimAt: 1400, retain: 800
      ),
      forKey: self.wordKey
    )
    _ = ConfirmedChoiceLearning.rememberConfirmedChinese(
      candidate.text, defaults: self.defaults
    )

    // Learn only the explicitly selected glyph under the canonical stroke
    // prefix. A match shared by Rime and Fcitx5 must not imply source bias.
    if candidate.mode == .stroke,
       let prefix = self.normalized(typedCode, mode: .stroke) {
      let key = prefix + "|" + candidate.text
      let choices = self.defaults?.dictionary(forKey: self.strokePrefixKey)
        as? [String: Int] ?? [:]
      self.defaults?.set(
        ConfirmedChoiceLearning.increment(
          key, in: choices, maximum: 160, trimAt: 1400, retain: 800
        ),
        forKey: self.strokePrefixKey
      )
    }

    guard !candidate.ambiguousVariant, candidate.variant == 3 || candidate.variant == 5
    else { return }
    let key = candidate.mode.rawValue + "." + String(candidate.variant)
    var generation = self.defaults?.dictionary(forKey: self.generationKey)
      as? [String: Int] ?? [:]
    if generation.values.reduce(0, +) >= 120 {
      for key in generation.keys { generation[key] = (generation[key] ?? 0) / 2 }
    }
    generation[key] = min(120, (generation[key] ?? 0) + 1)
    self.defaults?.set(generation, forKey: self.generationKey)
  }

  private static let baseFont = CTFontCreateWithName(
    "PingFangHK-Regular" as CFString, 18, nil
  )

  private static func canDisplay(_ text: String) -> Bool {
    guard !text.isEmpty, !text.unicodeScalars.contains(where: {
      [0xFFFD, 0x25A1, 0x25AF].contains($0.value)
    }) else { return false }
    for character in text {
      let fragment = String(character)
      let fallback = CTFontCreateForString(
        baseFont, fragment as CFString, CFRange(location: 0, length: fragment.utf16.count)
      )
      let fontName = CTFontCopyPostScriptName(fallback) as String
      if fontName.localizedCaseInsensitiveContains("LastResort") { return false }
      let scalars = Array(fragment.utf16)
      var glyphs = [CGGlyph](repeating: 0, count: scalars.count)
      let valid = scalars.withUnsafeBufferPointer { chars in
        glyphs.withUnsafeMutableBufferPointer { output in
          CTFontGetGlyphsForCharacters(
            fallback, chars.baseAddress!, output.baseAddress!, chars.count
          )
        }
      }
      if !valid { return false }
    }
    return true
  }

  private func normalized(_ raw: String, mode: ChineseInputMode) -> String? {
    let code = raw.lowercased()
    guard !code.isEmpty,
          code.count <= (mode == .stroke ? 64 : 6) else { return nil }
    let allowed = mode == .stroke ? "nm,./" : "abcdefghijklmnopqrstuvwxyz"
    return code.allSatisfy { allowed.contains($0) } ? code : nil
  }

  private struct Hit {
    let word: String
    let code: String
    let variant: Int
    let priority: Int
  }

  private func fetch(mode: ChineseInputMode, code: String,
                     prefix: Bool, limit: Int) -> [Hit] {
    guard let db = self.database else { return [] }
    // Short stroke prefixes use a precomputed top-240 index to avoid
    // sorting the whole full-length Rime dictionary on every key press.
    let shortStroke = mode == .stroke && prefix && code.count <= 3
    let sql = shortStroke
      ? "SELECT word,code,0 AS variant,priority FROM stroke_prefix WHERE prefix=? ORDER BY priority LIMIT ?"
      : prefix
        ? "SELECT word,code,variant,priority FROM entries WHERE method=? AND code>=? AND code<? AND code!=? ORDER BY priority LIMIT ?"
        : "SELECT word,code,variant,priority FROM entries WHERE method=? AND code=? ORDER BY priority LIMIT ?"
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK
    else { sqlite3_finalize(statement); return [] }
    defer { sqlite3_finalize(statement) }

    let destructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    func bind(_ string: String, index: Int32) {
      _ = string.withCString { sqlite3_bind_text(statement, index, $0, -1, destructor) }
    }
    if shortStroke {
      bind(code, index: 1)
      sqlite3_bind_int(statement, 2, Int32(limit))
    } else {
      bind(mode.rawValue, index: 1)
      bind(code, index: 2)
      if prefix {
        bind(code + "\u{10FFFF}", index: 3)
        bind(code, index: 4)
        sqlite3_bind_int(statement, 5, Int32(limit))
      } else {
        sqlite3_bind_int(statement, 3, Int32(limit))
      }
    }

    var result = [Hit]()
    while sqlite3_step(statement) == SQLITE_ROW {
      guard let rawWord = sqlite3_column_text(statement, 0),
            let rawCode = sqlite3_column_text(statement, 1) else { continue }
      result.append(Hit(
        word: String(cString: rawWord),
        code: String(cString: rawCode),
        variant: Int(sqlite3_column_int(statement, 2)),
        priority: Int(sqlite3_column_int64(statement, 3))
      ))
    }
    return result
  }
}
