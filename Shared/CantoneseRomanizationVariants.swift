import Foundation

/// Alternative untoned input spellings. Standard Jyutping and Yale remain
/// indexed first; these aliases are only extra, lower-ranked candidate paths.
enum CantoneseRomanizationVariants {
  static func variants(for input: String, limit: Int = 12) -> [String] {
    let source = input.lowercased()
    guard !source.isEmpty, source.count <= 48,
          source.allSatisfy({ $0.isASCII && $0.isLetter }) else { return [] }

    let replacements: [(String, String)] = [
      ("yyu", "yu"), ("yyun", "yun"), ("yuen", "yun"),
      ("yun", "yuen"), ("yue", "yu"), ("yu", "yyu"),
      ("eui", "ui"), ("ui", "eui"), ("oei", "eui"),
      ("eui", "oei"), ("oe", "eu"), ("eu", "oe"),
      ("eo", "eu"), ("aa", "a"), ("a", "aa")
    ]
    var results = [source]
    var seen: Set<String> = [source]
    // One edit first; only a bounded number of combined alternatives.
    for pass in 0..<2 {
      let bases = pass == 0 ? [source] : Array(results.dropFirst().prefix(6))
      for base in bases {
        for (old, new) in replacements where base.contains(old) {
          let candidate = base.replacingOccurrences(of: old, with: new)
          if candidate.count <= 48 && seen.insert(candidate).inserted {
            results.append(candidate)
            if results.count >= max(1, limit) { return results }
          }
        }
      }
    }
    return results
  }
}
