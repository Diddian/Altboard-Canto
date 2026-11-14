import Foundation

@main
enum VerifySpeechRecommendations {
  static func expect(
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

  static func main() {
    expect(["yue"], .qwen3ASR17BCantoneseHK)
    expect(["yue", "en"], .qwen3ASR17BCantoneseHK)
    expect(["yue", "en", "de"], .qwen3ASR17B)
    expect(["yue", "en"], .qwen3ASR06B, supported: {
      $0 != .qwen3ASR17BCantoneseHK && $0 != .qwen3ASR17B
    })
    expect(["yue", "en"], .senseVoiceSmall,
      supported: { $0 != .qwen3ASR17BCantoneseHK && $0 != .qwen3ASR17B && $0 != .qwen3ASR06B })
    expect(["yue", "de"], .whisperSmall,
      supported: { $0 != .qwen3ASR17BCantoneseHK && $0 != .qwen3ASR17B && $0 != .qwen3ASR06B })
    expect(["en", "de"], .parakeetV3)
    expect(["ru", "ja"], .whisperSmall)
    expect([], .whisperSmall)
    print("Speech-language model recommendations: passed")
  }
}
