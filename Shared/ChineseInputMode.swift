import Foundation

enum ChineseInputMode: String, CaseIterable, Sendable {
  case phonetic
  case quick
  case cangjie
  case stroke

  var title: String {
    switch self {
    case .phonetic: "拼音"
    case .quick: "速成"
    case .cangjie: "倉頡"
    case .stroke: "筆劃"
    }
  }

  var shortTitle: String {
    switch self {
    case .phonetic: "拼"
    case .quick: "速"
    case .cangjie: "倉"
    case .stroke: "筆"
    }
  }

  var usesShapeTable: Bool { self != .phonetic }
  var isAlphabetic: Bool { self != .stroke }

  var next: Self {
    let modes = Self.allCases
    let index = modes.firstIndex(of: self) ?? 0
    return modes[(index + 1) % modes.count]
  }
}

/// Stable language-to-method registry. New language families can register new
/// descriptors without reusing a Cantonese phonetic or shape dictionary.
struct InputMethodDescriptor: Hashable, Sendable {
  let languageTag: String
  let identifier: String
  let title: String
  let shortTitle: String
}

enum InputMethodCatalog {
  static let methods: [InputMethodDescriptor] = ChineseInputMode.allCases.map {
    InputMethodDescriptor(
      languageTag: "yue", identifier: "yue." + $0.rawValue,
      title: $0.title, shortTitle: $0.shortTitle
    )
  }

  static func available(for preferredLanguages: [String]) -> [InputMethodDescriptor] {
    methods.filter { preferredLanguages.contains($0.languageTag) }
  }
}

/// Physical Cangjie/Quick radical guide. The underlying character keys are
/// unchanged; only the small secondary keycap label changes by input mode.
enum ChineseShapeKeys {
  private static let radicals = Array("日月金木水火土竹戈十大中一弓人心手口尸廿山女田難卜重")
  private static let alphabet = Array("abcdefghijklmnopqrstuvwxyz")
  private static let hints: [String: String] = {
    Dictionary(uniqueKeysWithValues: zip(alphabet, radicals).map {
      (String($0.0), String($0.1))
    })
  }()

  static func hint(for key: String, mode: ChineseInputMode) -> String? {
    guard mode == .quick || mode == .cangjie else { return nil }
    return hints[key.lowercased()]
  }
}

/// Five Hong Kong stroke keys in screenshot order. Fcitx5 Stroke5 uses
/// m=horizontal, /=vertical, comma=left-falling, period=dot, n=turn.
enum ChineseStrokeKeys {
  struct Key: Sendable {
    let glyph: String
    let code: String
    let accessibilityName: String
  }

  static let keys: [Key] = [
    Key(glyph: "一", code: "m", accessibilityName: "橫"),
    Key(glyph: "丨", code: "/", accessibilityName: "豎"),
    Key(glyph: "丿", code: ",", accessibilityName: "撇"),
    Key(glyph: "丶", code: ".", accessibilityName: "點"),
    Key(glyph: "乛", code: "n", accessibilityName: "折")
  ]
  /// Long-press symbols follow the matching part of the number/symbol
  /// keyboard: a two-row, four-column strip for each upper stroke key.
  /// The lower keys expose Chinese punctuation in the same touch gesture.
  static let alternates: [[String]] = [
    ["1", "2", "3", "4", "-", "/", ":", ";"],
    ["4", "5", "6", "7", ";", "(", ")", "$"],
    ["7", "8", "9", "0", "$", "&", "@", "\""],
    ["。", "，", "？"],
    ["？", "！", "「", "」"]
  ]
  /// Positive horizontal movement always selects the option to the right.
  /// Edge keys begin from the reachable side, not the middle of the popup.
  static func popupStartIndex(keyIndex: Int, optionCount: Int) -> Int {
    guard optionCount > 0 else { return 0 }
    if keyIndex == 0 { return 0 }
    if keyIndex == 2 { return optionCount - 1 }
    return optionCount / 2
  }

  static func popupIndex(horizontalDelta: Double, optionCount: Int,
                         columnWidth: Double, startIndex: Int? = nil) -> Int {
    guard optionCount > 0 else { return 0 }
    let steps = Int((horizontalDelta / max(1, columnWidth)).rounded())
    let initial = startIndex ?? optionCount / 2
    return min(optionCount - 1, max(0, initial + steps))
  }

  static func glyphs(for code: String) -> String {
    let values = Dictionary(uniqueKeysWithValues: keys.map { ($0.code, $0.glyph) })
    return code.map { values[String($0)] ?? String($0) }.joined()
  }
}

/// Pure, bounded scoring primitive. Personal choices never change the source
/// codes. Ambiguous 3rd/5th-generation matches are not treated as evidence
/// of a user's generation preference.
enum ChineseShapeRanking {
  static func score(priority: Int, variant: Int, preferred: Int,
                    count: Int, exact: Bool, sharedCount: Int = 0) -> Int {
    let versionPenalty = variant == preferred || variant == 0 ? 0 : 90_000
    let remembered = min(80, max(0, count)) * 2_000
    // Shared confirmed Han words only break close ties. Exact codes and
    // generation-specific evidence retain their existing priority.
    let crossMethod = min(8, max(0, sharedCount)) * 750
    return (exact ? 0 : 2_000_000_000) + priority / 10
      + versionPenalty - remembered - crossMethod
  }

  /// An explicit choice for this canonical stroke prefix (not an upstream
  /// source) can move frequent glyphs ahead of equally plausible candidates.
  static func strokeChoiceBonus(_ count: Int) -> Int {
    min(60, max(0, count)) * 8_000
  }

  static func preferredVariant(_ counts: [String: Int], mode: ChineseInputMode) -> Int {
    let prefix = mode.rawValue + "."
    let three = counts[prefix + "3"] ?? 0
    let five = counts[prefix + "5"] ?? 0
    // A weak HK third-generation prior. Learned explicit selections can
    // override it, and counts are aged so habits can change later.
    return five > three + 2 ? 5 : 3
  }
}
