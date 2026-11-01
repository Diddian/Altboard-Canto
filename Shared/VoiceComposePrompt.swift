import Foundation

enum VoiceComposeKind: String, Sendable {
  case whatsapp
  case email
  case letter
  case message
  case unspecified

  static func detect(in transcript: String) -> Self {
    let input = transcript.lowercased()
    func containsAny(_ choices: [String]) -> Bool {
      choices.contains { input.contains($0) }
    }
    // A specific medium takes precedence over the generic word "message".
    if containsAny(["whatsapp", "whats app", "whatsap", "wa訊息", "wa信息"]) {
      return .whatsapp
    }
    if containsAny(["email", "e-mail", "e mail", "電郵", "電子郵件", "电子邮件",
                    "郵件", "邮件"]) {
      return .email
    }
    if containsAny(["formal letter", "write a letter", "write me a letter",
                    "schreib einen brief", "schreibe einen brief", "brief an",
                    "封信", "寫信", "写信", "信件"]) {
      return .letter
    }
    if containsAny(["message", "textnachricht", "nachricht", "訊息", "短訊",
                    "信息", "短信", "短消息"]) {
      return .message
    }
    return .unspecified
  }

  var formatHint: String {
    switch self {
    case .whatsapp:
      "WhatsApp message: brief, conversational, authentic everyday language. No subject or formal signature."
    case .email:
      "Email: appropriate greeting, coherent short paragraphs and closing. Include a subject only if explicitly requested."
    case .letter:
      "Letter: structured paragraphs, suitable greeting and closing, formal unless told otherwise."
    case .message:
      "Chat/SMS: concise natural conversational language."
    case .unspecified:
      "Infer the requested writing format from the speaker; if ambiguous, produce a concise message."
    }
  }
}

enum VoiceComposePrompt {
  static func systemPrompt(
    for options: VoiceOutputConfiguration,
    spokenInstruction: String
  ) -> String {
    let medium = VoiceComposeKind.detect(in: spokenInstruction)
    let language: String
    if options.target == .original {
      language = "Use the language the speaker explicitly requests; otherwise use their main spoken language, retaining natural code-switching."
    } else {
      language = "OVERRIDING KEYBOARD OUTPUT LANGUAGE: "
        + (options.target.targetInstruction(customLanguage: options.customLanguage)
           ?? "Use the spoken language.")
        + " The keyboard-selected output language takes precedence over any spoken instruction."
    }
    return """
      You are an OFFLINE MULTILINGUAL WRITING ASSISTANT, not a dictation editor. \
      Understand instructions spoken in Cantonese (香港廣東話), Traditional Chinese, \
      Mandarin, English or German, including code-switching. \
      Write the FINISHED text requested by the speaker, not a transcript of their instructions. \
      Infer WhatsApp, email, formal letter or another medium from the utterance itself. \
      Detected medium: \(medium.formatHint) \
      WhatsApp is ALWAYS casual and conversational, with short paragraphs; \
      never write a formal letter, subject line or invented sign-off for WhatsApp. \
      Email needs an appropriate greeting/closing. Letter needs a suitable structure. \
      Respect explicit tone requests unless they conflict with the WhatsApp default. \
      \(language) \
      For Cantonese output, use natural HONG KONG SPOKEN CANTONESE in Traditional Chinese, \
      e.g. 唔、冇、喺、嘅、咗、啲、佢、畀、而家、點解. Never write Mandarin or generic 書面語. \
      Actually translate English, German or written Chinese sentences to spoken Cantonese \
      when Cantonese is selected; proper names and essential technical terms may remain. \
      Preserve supplied facts, names, dates, amounts, conditional phrases and negation. \
      Do NOT invent facts, names, addresses, recipients or promises; omit unknown particulars \
      or use neutral placeholders only where needed. \
      Use blank lines between paragraphs where appropriate. \
      Output ONLY the finished text, with no explanation or markdown fences.
      """
  }

  static let cantoneseRepairPrompt = """
    Translate or rewrite the following text ENTIRELY into natural Hong Kong SPOKEN \
    CANTONESE written in Traditional Chinese. Do not use Mandarin, generic 書面語, \
    or unconverted English/German sentences. Keep proper names and essential technical terms. \
    Use words like 唔、冇、喺、嘅、啲、咗、畀、佢 naturally. \
    Preserve every fact, condition, negation, number and the paragraph structure. \
    Output ONLY the Cantonese result.
    """

  static func needsCantoneseRetry(output: String, target: VoiceOutputTarget) -> Bool {
    guard target == .cantonese else { return false }
    let outputHasHan = output.unicodeScalars.contains { (0x3400...0x9FFF).contains($0.value) }
    if !outputHasHan {
      return !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // Retry only obvious formal/Mandarin drift, not ordinary mixed Cantonese
    // with technical English words or standard Chinese proper names.
    let formalMarkers = ["我們", "你們", "他們", "沒有", "現在", "應該", "這個", "這樣", "这是", "他们"]
    let colloquialMarkers = ["唔", "冇", "喺", "嘅", "咗", "啲", "畀", "噉"]
    return formalMarkers.contains(where: { output.contains($0) })
      && !colloquialMarkers.contains(where: { output.contains($0) })
  }
}
