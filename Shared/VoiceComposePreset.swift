import Foundation
import NaturalLanguage

/// The suggestion-bar selection controls writing format and register,
/// independently from the keyboard's AUTO / 粵 / EN / DE output-language key.
enum VoiceComposePreset: String, CaseIterable, Identifiable, Codable, Sendable {
  case automatic
  case whatsapp
  case email
  case letter
  case professional
  case formal
  case casual

  var id: String { rawValue }

  var label: String {
    switch self {
    case .automatic: "Auto"
    case .whatsapp: "WhatsApp"
    case .email: "Email"
    case .letter: "Letter"
    case .professional: "Business"
    case .formal: "Formal"
    case .casual: "Casual"
    }
  }

  var formatOverride: VoiceComposeKind? {
    switch self {
    case .whatsapp: .whatsapp
    case .email: .email
    case .letter: .letter
    default: nil
    }
  }

  var toneInstruction: String? {
    switch self {
    case .professional:
      "Use concise, courteous, professional business language suited to clients and tenants."
    case .formal:
      "Use polished, formal, respectful language without unnecessary elaboration."
    case .casual:
      "Use natural conversational language and everyday phrasing; do not add forced enthusiasm."
    case .whatsapp:
      "Use natural, brief, conversational WhatsApp language, not a letter or email."
    case .email, .letter, .automatic:
      nil
    }
  }
}

enum VoiceComposeLanguage {
  /// Prefer the recognizer's language tag when available. Qwen3-ASR's
  /// sherpa-onnx result may leave this empty; then use the transcript itself.
  static func detectedCode(transcript: String, reported: String? = nil) -> String {
    let colloquialCantonese = ["我哋", "你哋", "佢哋", "唔", "冇", "喺", "嘅", "啲", "咗", "畀"]
    let isCantonese = colloquialCantonese.contains { transcript.contains($0) }

    if let reported, !reported.isEmpty {
      let lower = reported.lowercased()
      if lower.hasPrefix("en") { return "en" }
      if lower.hasPrefix("de") { return "de" }
      if lower == "yue" || lower == "zh-yue" { return "yue" }
      if lower.hasPrefix("zh") { return isCantonese ? "yue" : "zh" }
    }
    let recognizer = NLLanguageRecognizer()
    recognizer.processString(transcript)
    switch recognizer.dominantLanguage {
    case .english: return "en"
    case .german: return "de"
    case .simplifiedChinese, .traditionalChinese:
      return isCantonese ? "yue" : "zh"
    default:
      let hasHan = transcript.unicodeScalars.contains { (0x3400...0x9FFF).contains($0.value) }
      if isCantonese { return "yue" }
      return hasHan ? "zh" : "en"
    }
  }

  static func displayName(for code: String) -> String {
    switch code {
    case "en": "English"
    case "de": "German (Deutsch)"
    case "yue": "spoken Hong Kong Cantonese (Traditional Chinese)"
    case "zh": "Chinese, preserving the spoken register (Traditional Chinese)"
    default: "the spoken language"
    }
  }
}
