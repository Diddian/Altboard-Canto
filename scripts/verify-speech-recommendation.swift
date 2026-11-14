import Foundation

func expect(
  _ languages: [String], _ expected: ModelVariant,
  supported: (ModelVariant) -> Bool = { _ in true }
) {
  let actual = SpeechModelRecommendation.recommendedVariant(
    languages: languages, isSupported: supported
  )
  precondition(actual == expected, "Expected \(expected) for \(languages), got \(actual)")
  precondition(Set(languages).isSubset(of: actual.supportedLanguages) || languages.isEmpty,
               "Recommended model does not cover all chosen languages")
}

expect(["yue"], .senseVoiceSmall)
expect(["yue", "en"], .senseVoiceSmall)
expect(["yue", "zh", "en"], .senseVoiceSmall)
expect(["yue", "en", "de"], .qwen3ASR06B)
expect(["yue", "de"], .qwen3ASR06B)
expect(["yue", "en"], .qwen3ASR06B, supported: { $0 != .senseVoiceSmall })
expect(["yue", "de"], .whisperSmall, supported: { $0 != .qwen3ASR06B })
expect(["en", "de"], .parakeetV3)
expect(["ru", "ja"], .whisperSmall)
expect([], .whisperSmall)
print("Speech-language model recommendations: passed")
