import Foundation

enum SpeechModelRecommendation {

  static func speechCode(forIdentifier identifier: String) -> String? {
    guard let base = Locale(identifier: identifier).language.languageCode?.identifier else { return nil }
    let code = self.whisperAliases[base] ?? base
    return SpeechLanguages.all.contains(code) ? code : nil
  }

  static func speechCodes(from identifiers: [String]) -> [String] {
    var seen = Set<String>()
    return identifiers.compactMap(self.speechCode(forIdentifier:)).filter { seen.insert($0).inserted }
  }

  static func recommendedVariant(
    languages: [String],
    isSupported: (ModelVariant) -> Bool = { $0.isSupportedOnCurrentDevice },
  ) -> ModelVariant {
    let wanted = self.wanted(languages)
    if wanted.contains("yue") {
      // Prefer the existing lightweight WSYue recognizer for Cantonese when
      // it covers all chosen languages. Never silently drop German or others.
      if wanted.isSubset(of: ModelVariant.senseVoiceSmall.supportedLanguages),
         isSupported(.senseVoiceSmall) {
        return .senseVoiceSmall
      }
      // The supported 0.6B ONNX runtime covers Cantonese + German/English.
      // The new HK-tuned GGUF checkpoints require a different ASR runtime.
      if wanted.isSubset(of: ModelVariant.qwen3ASR06B.supportedLanguages),
         isSupported(.qwen3ASR06B) {
        return .qwen3ASR06B
      }
    }
    if wanted.isSubset(of: SpeechLanguages.parakeetV3), isSupported(.parakeetV3) {
      return .parakeetV3
    }
    return self.whisperFallbacks.first(where: isSupported) ?? .whisperTiny
  }

  static func alternatives(
    languages: [String],
    excluding recommended: ModelVariant,
    isSupported: (ModelVariant) -> Bool = { $0.isSupportedOnCurrentDevice },
  ) -> [ModelVariant] {
    let wanted = self.wanted(languages)
    let candidates = ModelVariant.allCases.filter { variant in
      variant != recommended && isSupported(variant) && wanted.isSubset(of: variant.supportedLanguages)
    }
    return Array(candidates.sorted { $0.catalogRank > $1.catalogRank }.prefix(self.alternativesLimit))
  }

  static func preferredLanguages(for variant: ModelVariant, from languages: [String]) -> Set<String> {
    guard variant.supportsLanguageSelection else { return [] }
    return Set(languages).intersection(variant.supportedLanguages)
  }

  private static let whisperAliases = ["nb": "no", "jv": "jw", "fil": "tl"]
  private static let whisperFallbacks: [ModelVariant] = [.whisperSmall, .whisperBase, .whisperTiny]
  private static let alternativesLimit = 3

  private static func wanted(_ languages: [String]) -> Set<String> {
    languages.isEmpty ? SpeechLanguages.all : Set(languages)
  }
}
