import Foundation

enum VoiceComposeKind: String, Sendable {
  case whatsapp, email, letter, message, unspecified

  static func detect(in transcript: String) -> Self {
    let input = transcript.lowercased()
    func has(_ words: [String]) -> Bool { words.contains { input.contains($0) } }
    if has(["whatsapp", "whats app", "whatsap"]) { return .whatsapp }
    if has(["email", "e-mail", "e mail", "電郵", "電子郵件", "电子邮件", "郵件"]) { return .email }
    if has(["letter", "brief", "封信", "寫信", "写信", "信件"]) { return .letter }
    if has(["message", "nachricht", "訊息", "短訊", "信息", "短信"]) { return .message }
    return .unspecified
  }

  var instruction: String {
    switch self {
    case .whatsapp: "Write a natural, concise and conversational WhatsApp message. No subject line or formal sign-off."
    case .email: "Write an email with an appropriate greeting, short paragraphs and closing. Include a subject only if asked."
    case .letter: "Write a structured letter with suitable greeting, paragraphs and closing. Default to formal if tone is unspecified."
    case .message: "Write a concise conversational chat message."
    case .unspecified: "Infer the writing format from the spoken request. When unclear, use a concise message."
    }
  }
}

enum VoiceComposePrompt {
  static func systemPrompt(for options: VoiceOutputConfiguration, instruction: String) -> String {
    let language: String
    if options.target == .original {
      language = "Write in the language requested by the speaker, otherwise the main spoken language. Preserve natural code-switching where requested."
    } else {
      language = "OVERRIDING OUTPUT LANGUAGE: " +
        (options.target.targetInstruction(customLanguage: options.customLanguage)
          ?? "Use the spoken language.")
        + " Follow the selected keyboard output language even if the spoken request names another language."
    }
    return """
      You are an OFFLINE multilingual writing assistant. Understand spoken instructions in \
      Hong Kong Cantonese, Mandarin, English or German, including mixed-language sentences. \
      Produce the FINISHED writing, not a transcript, explanation, or reply to the speaker. \
      Detect the requested form: WhatsApp, email, letter, message or other text. \
      \(VoiceComposeKind.detect(in: instruction).instruction) \
      WhatsApp must sound like a real chat, not a formal email, regardless of the generic style setting. \
      Respect explicitly requested tone if compatible with the medium. \
      \(language) \
      For Cantonese, use authentic HONG KONG SPOKEN CANTONESE in Traditional Chinese, \
      with natural colloquial words such as 唔、冇、喺、嘅、啲、咗、佢、畀. Do not write Mandarin or 書面語. \
      Preserve facts, figures, negations, names and conditions. Never invent dates, promises, \
      people's names, addresses or circumstances. Use paragraphs when helpful. \
      Output ONLY the finished text.
      """
  }

  static let cantoneseRepairPrompt = """
    Rewrite the supplied text entirely as natural Hong Kong SPOKEN CANTONESE \
    in Traditional Chinese. Do not write English sentences, Mandarin or formal 書面語. \
    Preserve the facts and proper names. Return only the revised text.
    """

  static func needsCantoneseRepair(_ text: String, target: VoiceOutputTarget) -> Bool {
    guard target == .cantonese, !text.isEmpty else { return false }
    return !text.unicodeScalars.contains { (0x3400...0x9FFF).contains($0.value) }
  }
}
