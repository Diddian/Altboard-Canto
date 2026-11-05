import Foundation

// Standalone prompt dependencies; no app, model download or inference is started.
enum ChatTemplate { case chatml, qwenNoThinking, gemma, llama }
enum LLMAction {
  case translate, removeRedundancy, rewrite, formal, casual, fixGrammar, simplify
  case continueWriting, shorten, bulletPoints, summarize, expand, addPunctuation
}
struct LLMCustomPrompt { let prompt: String }

@main
enum VerifyLLMDevicePolicy {
  static func main() {
    precondition(LLMDevicePolicy.usesChinese(["en", "yue-HK"]))
    precondition(LLMDevicePolicy.usesChinese(["zh_Hant_TW"]))
    precondition(!LLMDevicePolicy.usesChinese(["en", "de"]))
    precondition(!LLMDevicePolicy.usesChinese(["xyue"]))
    precondition(LLMDevicePolicy.recommendedTier(
      physicalBytes: 12_884_901_888, availableBytes: 9_000_000_000
    ) == .large)
    // A 12 GB device does not imply that this app can allocate 9B's working set.
    precondition(LLMDevicePolicy.recommendedTier(
      physicalBytes: 12_884_901_888, availableBytes: 4_000_000_000
    ) == .balanced)
    precondition(LLMDevicePolicy.recommendedTier(
      physicalBytes: 6_442_450_944, availableBytes: 3_000_000_000
    ) == .balanced)
    precondition(LLMDevicePolicy.recommendedTier(
      physicalBytes: 4_294_967_296, availableBytes: 2_000_000_000
    ) == .compact)
    precondition(LLMDevicePolicy.recommendedTier(
      physicalBytes: 12_884_901_888, availableBytes: 0
    ) == .compact)
    let required = LLMDevicePolicy.requiredMemoryBytes(for: .large)
    precondition(!LLMDevicePolicy.supports(.large, physicalBytes: 12_884_901_888, availableBytes: required - 1))
    precondition(LLMDevicePolicy.supports(.large, physicalBytes: 12_884_901_888, availableBytes: required))
    for language in ["zh", "zh-Hant", "zh-Hans", "yue", "yue-HK"] {
      let prompt = LLMPromptTemplates.systemPrompt(for: .rewrite, language: language)
      precondition(prompt.contains("Traditional Chinese"))
      precondition(prompt.contains("political and historical"))
      precondition(prompt.contains("Do not replace them"))
    }
    print("Device memory tiers and Chinese rewrite prompt contracts passed")
  }
}
