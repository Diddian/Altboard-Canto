import Foundation

enum LanguagePriority {
  static func code(_ value: String) -> String {
    let lower = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: "_", with: "-")
    if lower == "zh-hk" || lower.hasPrefix("zh-hant-hk") { return "yue" }
    let base = lower.split(separator: "-").first.map(String.init) ?? ""
    return base == "cmn" ? "zh" : base
  }

  static func ordered(_ values: [String], available: Set<String>? = nil) -> [String] {
    var seen = Set<String>()
    return values.map(self.code).filter {
      !$0.isEmpty && (available?.contains($0) ?? true) && seen.insert($0).inserted
    }
  }

  /// A bounded prior: actual word context and confirmed selections can outweigh it.
  static func boosts(_ preferred: [String]) -> [String: Int] {
    Dictionary(uniqueKeysWithValues: self.ordered(preferred).enumerated().map {
      ($0.element, max(0, 6 - $0.offset) * 3)
    })
  }

  static func boost(for language: String, preferred: [String]) -> Int {
    self.boosts(preferred)[self.code(language)] ?? 0
  }

  static func moving(_ values: [String], offsets: IndexSet, to destination: Int) -> [String] {
    let valid = offsets.filter { values.indices.contains($0) }
    let moved = valid.map { values[$0] }
    var remaining = values.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
    let insertion = max(0, min(remaining.count, destination - valid.filter { $0 < destination }.count))
    remaining.insert(contentsOf: moved, at: insertion)
    return remaining
  }
}
