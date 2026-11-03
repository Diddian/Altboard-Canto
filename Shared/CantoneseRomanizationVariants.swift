import Foundation

/// The regular systems are directly indexed in SQLite. Only narrowly scoped
/// colloquial aliases remain here, avoiding combinatorial false homophones.
enum CantoneseRomanizationVariants {
  static func variants(for input: String, limit: Int = 4) -> [String] {
    let source = input.lowercased()
    guard !source.isEmpty, source.count <= 96,
          source.allSatisfy({ $0.isASCII && $0.isLetter }) else { return [] }
    var results = [source]
    var seen: Set<String> = [source]
    func append(_ value: String) {
      guard value.count <= 96, seen.insert(value).inserted else { return }
      results.append(value)
    }
    if source == "mm" || source == "mmm" { append("m") }
    // ng is a legitimate syllable in its own right; its original matches
    // are still ranked above the optional m4 ("唔") candidate.
    if source == "ng" { append("m") }
    // Cantonese 唔 is routinely typed ng as well as m. Preserve the
    // exact ng reading, then try m at a word boundary before 係 (hai).
    // Never generalize ng -> m across every syllable or English word.
    if source == "nghai" || source == "nghaai" {
      append("m" + source.dropFirst(2))
    }
    // Common colloquial spellings of 唔係呀嘛 (m4 hai6 aa3 maa3).
    // The extra h is a typed colloquial variant, not a general vowel rule.
    if ["nghaiahma", "nghaiama", "nghaiaama", "nghaiamaa",
        "nghaiaamaa", "mhaiama", "mhaiahma"].contains(source) {
      append("mhaiaamaa")
    }
    if source.contains("yyu") {
      append(source.replacingOccurrences(of: "yyu", with: "yu"))
    }
    return Array(results.prefix(max(1, limit)))
  }
}
