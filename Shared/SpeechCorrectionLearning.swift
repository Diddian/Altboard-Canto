import Foundation

/// Explicitly corrected recordings provide paired local ASR examples.
/// This class does not modify Qwen ONNX weights or upload voice recordings.
enum SpeechCorrectionLearning {
  struct Pair: Hashable, Sendable {
    let heard: String
    let intended: String
  }

  /// Extract only one small localized difference. Entirely rewritten
  /// paragraphs are not a reliable pronunciation training signal.
  static func pair(heard: String, intended: String) -> Pair? {
    guard heard != intended, !heard.isEmpty, !intended.isEmpty,
          heard.count <= 2_000, intended.count <= 2_000 else { return nil }
    let old = Array(heard), new = Array(intended)
    var prefix = 0
    while prefix < min(old.count, new.count)
      && old[prefix] == new[prefix] { prefix += 1 }
    var suffix = 0
    while suffix < min(old.count - prefix, new.count - prefix)
      && old[old.count - 1 - suffix] == new[new.count - 1 - suffix] {
      suffix += 1
    }

    var wrong = Array(old[prefix..<(old.count - suffix)])
    var right = Array(new[prefix..<(new.count - suffix)])
    guard !wrong.isEmpty, !right.isEmpty,
          wrong.count <= 24, right.count <= 24 else { return nil }

    // The existing correction engine requires two characters of context.
    // Extend a single-Han-character substitution by one shared neighbor.
    if (wrong.count < 2 || right.count < 2) && prefix > 0 {
      wrong.insert(old[prefix - 1], at: 0)
      right.insert(new[prefix - 1], at: 0)
    } else if (wrong.count < 2 || right.count < 2) && suffix > 0 {
      wrong.append(old[old.count - suffix])
      right.append(new[new.count - suffix])
    }
    let before = String(wrong), after = String(right)
    guard (2...32).contains(before.count), (2...32).contains(after.count),
          before != after, hasHan(before), hasHan(after) else { return nil }
    return Pair(heard: before, intended: after)
  }

  private static func hasHan(_ text: String) -> Bool {
    text.unicodeScalars.contains { scalar in
      (0x3400...0x9FFF).contains(Int(scalar.value))
        || (0x20000...0x323AF).contains(Int(scalar.value))
    }
  }

  /// At least three different recordings must independently support one
  /// unambiguous correction before it becomes a reusable phrase rule.
  static func recurringPairs(in records: [HistoryRecord], minimumCount: Int = 3)
    -> [Pair] {
    var counts = [Pair: Int]()
    for record in records {
      guard let corrected = record.userCorrection,
            let candidate = pair(
              heard: record.originalASR ?? record.transcription,
              intended: corrected
            ) else { continue }
      counts[candidate, default: 0] += 1
    }
    let conflicting = Dictionary(grouping: counts.keys, by: \.heard)
      .filter { $0.value.count > 1 }.keys
    return counts.filter {
      $0.value >= minimumCount && !conflicting.contains($0.key.heard)
    }.map(\.key).sorted { $0.heard < $1.heard }
  }
}
