import Foundation

/// Bounded, explicit-choice-only evidence for romanization ordering.
enum CantoneseSchemePreference {
  static let keys = ["plain", "yale", "sidney"]
  static let traditionalKey = "traditional"
  static let colloquialNgKey = "negative_ng"
  static let canonicalMKey = "negative_m"
  static let evidenceKeys = keys + [traditionalKey, colloquialNgKey, canonicalMKey]
  static let preferenceStorageKey = "canto.ime.schemePreferenceCounts.v1"
  static let candidateStorageKey = "canto.jyutping.selectionCounts"

  /// Keep evidence local and bounded. Older confirmed selections gradually
  /// lose weight so a user can change spelling habits without a reset.
  static func recordingSelection(
    in counts: [String: Int], typed: String, canonical: String
  ) -> [String: Int] {
    let scheme = inferredScheme(input: typed, canonical: canonical)
    let negative = negativeParticleStyle(input: typed, canonical: canonical)
    guard scheme != nil || negative != nil else { return counts }
    var updated = counts
    if evidenceKeys.reduce(0, { $0 + max(0, updated[$1] ?? 0) }) >= 48 {
      for key in evidenceKeys { updated[key] = max(0, updated[key] ?? 0) / 2 }
    }
    for key in [scheme, negative].compactMap({ $0 }) {
      updated[key] = min(64, max(0, updated[key] ?? 0) + 1)
    }
    return updated
  }

  static func lookupOrder(_ counts: [String: Int]) -> [String] {
    switch preferred(counts) {
    case "yale": return ["yale", "sidney", "plain"]
    case "sidney": return ["sidney", "yale", "plain"]
    default: return keys
    }
  }

  static func prefersColloquialNg(_ counts: [String: Int]) -> Bool {
    let ng = max(0, counts[colloquialNgKey] ?? 0)
    let m = max(0, counts[canonicalMKey] ?? 0)
    return ng >= 3 && ng > m + 1
  }

  /// Only classify ng as 唔 when a confirmed candidate has an m4 syllable.
  /// Matching whole syllable sequences avoids rewriting ng in unrelated words.
  static func negativeParticleStyle(input: String, canonical: String) -> String? {
    let typed = input.lowercased()
    guard !typed.isEmpty, !typed.contains(where: \.isNumber) else { return nil }
    let syllables = canonical.lowercased().split(separator: " ").map(String.init)
    let positions = Array(syllables.indices.filter { syllables[$0] == "m4" }.prefix(4))
    guard !positions.isEmpty else { return nil }
    let partsByScheme = [
      syllables.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "123456")) },
      syllables.map(CantoneseSyllableEditing.yaleAlias),
      syllables.map(CantoneseSyllableEditing.sidneyLauAlias)
    ]
    for parts in partsByScheme {
      if parts.joined() == typed { return canonicalMKey }
      for mask in 1..<(1 << positions.count) {
        var withNg = parts
        for (bit, index) in positions.enumerated() where (mask & (1 << bit)) != 0 {
          withNg[index] = "ng"
        }
        if withNg.joined() == typed { return colloquialNgKey }
      }
    }
    return nil
  }
  static func inferredScheme(
    input: String, canonical: String
  ) -> String? {
    let typed = input.lowercased()
    guard !typed.isEmpty, !typed.contains(where: \.isNumber) else { return nil }
    let syllables = canonical.split(separator: " ").map(String.init)
    let variants = [
      "plain": syllables.map {
        $0.trimmingCharacters(in: CharacterSet(charactersIn: "123456"))
      }.joined(),
      "yale": syllables.map(CantoneseSyllableEditing.yaleAlias).joined(),
      "sidney": syllables.map(CantoneseSyllableEditing.sidneyLauAlias).joined()
    ]
    let matching = keys.filter { variants[$0] == typed }
    if matching.count == 1 { return matching[0] }
    // j- and ch- are shared by Yale and Sidney Lau. Record their
    // common family without pretending that they distinguish the two.
    if matching.count == 2 && matching.contains("yale")
      && matching.contains("sidney") { return traditionalKey }
    return nil
  }

  static func preferred(_ counts: [String: Int]) -> String? {
    let plain = counts["plain"] ?? 0
    let yale = counts["yale"] ?? 0
    let sidney = counts["sidney"] ?? 0
    let traditional = counts[traditionalKey] ?? 0
    let traditionalEvidence = traditional + yale + sidney

    // j/ch are shared by Yale and Sidney Lau; four explicit traditional
    // selections may prefer that family without asserting a specific scheme.
    if traditional >= 4 && traditionalEvidence > plain + 2 {
      return sidney > yale ? "sidney" : "yale"
    }

    let total = plain + yale + sidney
    guard total >= 12 else { return nil }
    let ranked = keys.sorted { (counts[$0] ?? 0) > (counts[$1] ?? 0) }
    let first = counts[ranked[0]] ?? 0
    let second = counts[ranked[1]] ?? 0
    guard first >= 7, first - second >= 4, first * 100 >= total * 55 else { return nil }
    return ranked[0]
  }
}

extension CantoneseSchemePreference {
  /// A deliberately narrow, shareable report. Persisted candidate keys can
  /// contain actual Chinese words; include only their aggregate counts.
  static func diagnosticJSON(
    counts: [String: Int],
    candidateCounts: [String: Int],
    groupAvailable: Bool,
    preferenceDataPresent: Bool,
    appVersion: String,
    appBuild: String,
    appCommit: String,
    keyboardCommit: String,
    generatedAt: Date
  ) throws -> Data {
    let safeCounts = Dictionary(uniqueKeysWithValues: evidenceKeys.map {
      ($0, max(0, counts[$0] ?? 0))
    })
    let totalEvidence = safeCounts.values.reduce(0, +)
    let savedChoices = candidateCounts.values.reduce(0) {
      $0 + min(10_000, max(0, $1))
    }
    let report: [String: Any] = [
      "schema_version": 1,
      "generated_at": ISO8601DateFormatter().string(from: generatedAt),
      "build": [
        "version": appVersion,
        "number": appBuild,
        "app_sha": appCommit,
        "keyboard_sha": keyboardCommit
      ],
      "storage": [
        "app_group_accessible": groupAvailable,
        "preference_data_present": preferenceDataPresent,
        "status": !groupAvailable ? "unavailable"
          : (totalEvidence == 0 ? "no_confirmed_selections" : "learning")
      ],
      "romanization": [
        "recent_weighted_counts": safeCounts,
        "total_weighted_evidence": totalEvidence,
        "preferred_scheme": preferred(safeCounts) ?? "undetermined",
        "lookup_priority": lookupOrder(safeCounts),
        "negative_ng_promoted": prefersColloquialNg(safeCounts)
      ],
      "candidate_learning": [
        "stored_candidate_count": candidateCounts.count,
        "stored_selection_weight": savedChoices
      ],
      "learning_policy": [
        "decay_threshold": 48,
        "negative_ng_min_confirmations": 3,
        "note": "Counts are weighted and decay; they are not lifetime keystroke totals."
      ],
      "privacy": [
        "raw_keystrokes_included": false,
        "candidate_words_included": false,
        "host_text_included": false,
        "recording_or_transcript_included": false
      ]
    ]
    return try JSONSerialization.data(
      withJSONObject: report, options: [.prettyPrinted, .sortedKeys]
    )
  }
}
