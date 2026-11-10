import Foundation

enum CantoneseOutput {
  /// Preserve English and German spans. A full OpenCC s2hk dictionary will be added after model tests.
  static func normalizeForOutput(
    _ text: String, options: VoiceOutputConfiguration
  ) -> String {
    if options.isSimplifiedChinese {
      // The selected output script must win over the default HK conversion.
      return VoiceOutputScriptPolicy.simplify(text)
    }
    switch options.target {
    case .cantonese, .traditionalChinese:
      return normalize(text)
    case .custom:
      // An explicit Traditional Chinese output may also be chosen by BCP-47 code.
      let code = options.customLanguage.lowercased()
      return ["zh-hant", "zh-hk", "zh-tw"].contains(code) ? normalize(text) : text
    case .original, .english, .german:
      return text
    }
  }

  static func normalize(_ text: String) -> String {
    let scalars = text.unicodeScalars
    let containsHan = scalars.contains { (0x3400...0x9FFF).contains($0.value) }
    let containsJapaneseKana = scalars.contains {
      (0x3040...0x30FF).contains($0.value)
    }
    guard containsHan, !containsJapaneseKana else { return text }
    return text.applyingTransform(StringTransform("Hans-Hant"), reverse: false) ?? text
  }
}
