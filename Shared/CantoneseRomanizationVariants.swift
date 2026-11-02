import Foundation

/// The regular systems are directly indexed in SQLite. Only narrowly scoped
/// colloquial aliases remain here, avoiding combinatorial false homophones.
enum CantoneseRomanizationVariants {
  static func variants(for input: String, limit: Int = 4) -> [String] {
    let source = input.lowercased()
    guard !source.isEmpty, source.count <= 48,
          source.allSatisfy({ $0.isASCII && $0.isLetter }) else { return [] }
    var results = [source]
    var seen: Set<String> = [source]
    func append(_ value: String) {
      guard value.count <= 48, seen.insert(value).inserted else { return }
      results.append(value)
    }
    if source == "mm" || source == "mmm" { append("m") }
    // ng is a legitimate syllable in its own right; its original matches
    // are still ranked above the optional m4 ("唔") candidate.
    if source == "ng" { append("m") }
    if source.contains("yyu") {
      append(source.replacingOccurrences(of: "yyu", with: "yu"))
    }
    return Array(results.prefix(max(1, limit)))
  }
}
