import Testing

@Suite("TextSanitizer")
struct TextSanitizerTests {

  @Test
  func `whisper special tokens`() {
    let input = "Hello <|endoftext|> world <|startoftranscript|>"
    #expect(TextSanitizer.sanitize(input) == "Hello world")
  }

  @Test
  func `hugging face unknown token`() {
    let input = "Hello <unk> world"
    #expect(TextSanitizer.sanitize(input) == "Hello world")
  }

  @Test
  func `square bracket annotations`() {
    let input = "Hello [Music] world [BLANK_AUDIO]"
    #expect(TextSanitizer.sanitize(input) == "Hello world")
  }

  @Test
  func `parenthesis annotations`() {
    let input = "Hello (Applause) world (Laughter)"
    #expect(TextSanitizer.sanitize(input) == "Hello world")
  }

  @Test
  func `musical note symbols`() {
    let input = "Hello \u{266A}\u{266B} world \u{2669}"
    #expect(TextSanitizer.sanitize(input) == "Hello world")
  }

  @Test
  func `unicode replacement character`() {
    let input = "Hello \u{FFFD} world"
    #expect(TextSanitizer.sanitize(input) == "Hello world")
  }

  @Test
  func `multiple artifact types`() {
    let input = "<|startoftranscript|> Hello <unk> [Music] \u{266A} world \u{FFFD} <|endoftext|>"
    #expect(TextSanitizer.sanitize(input) == "Hello world")
  }

  @Test
  func qwen3ControlHeaders() {
    #expect(TextSanitizer.sanitize("language Cantonese<asr_text>我而家好攰") == "我而家好攰")
    #expect(TextSanitizer.sanitize("language English<|asr_text|>Hello there") == "Hello there")
    #expect(TextSanitizer.sanitize("<asr_text>Ich komme morgen") == "Ich komme morgen")
    #expect(TextSanitizer.sanitize("language Cantonese is actual speech") ==
      "language Cantonese is actual speech")
  }

  @Test
  func qwen3UnpreferredLanguageHeaders() {
    #expect(TextSanitizer.sanitize("language French<asr_text>Bonjour") == "Bonjour")
    #expect(TextSanitizer.sanitize("language Japanese → ASR text → こんにちは") == "こんにちは")
    #expect(TextSanitizer.sanitize("language Spanish -> ASR text -> Hola") == "Hola")
    #expect(TextSanitizer.sanitize("language Chinese (Mandarin)<|asr_text|>你好") == "你好")
    #expect(TextSanitizer.sanitize("<|language|>Arabic<|asr_text|>مرحبا") == "مرحبا")
    #expect(TextSanitizer.sanitize("language: French → ASR text → Salut") == "Salut")
  }

  @Test
  func qwen3DoesNotEraseRealSpokenWords() {
    #expect(TextSanitizer.sanitize("language French is actual speech") ==
      "language French is actual speech")
    #expect(TextSanitizer.sanitize("I said language German → ASR text") ==
      "I said language German → ASR text")
    #expect(TextSanitizer.sanitize("Say ASR text in German") == "Say ASR text in German")
  }

  @Test
  func `live qwen chunks remove each repeated header`() {
    let first = TextSanitizer.sanitize("language Cantonese<asr_text>咁你睇唔睇到？")
    let second = TextSanitizer.sanitize("language Cantonese<asr_text>其實我而。")
    #expect(ExperimentalSpeechSegments.append(second, to: first) ==
      "咁你睇唔睇到？其實我而。")
  }

  @Test
  func `empty input`() {
    #expect(TextSanitizer.sanitize("").isEmpty)
  }

  @Test
  func `all artifacts returns empty`() {
    let input = "<|endoftext|> [Music] \u{266A} <unk> \u{FFFD}"
    #expect(TextSanitizer.sanitize(input).isEmpty)
  }

  @Test
  func `clean text passthrough`() {
    let input = "This is perfectly clean text."
    #expect(TextSanitizer.sanitize(input) == "This is perfectly clean text.")
  }

  @Test
  func `whitespace normalization`() {
    let input = "  Hello   world  "
    #expect(TextSanitizer.sanitize(input) == "Hello world")
  }

  @Test
  func `whitespace after artifact removal`() {
    let input = "Hello  [Music]  world"
    #expect(TextSanitizer.sanitize(input) == "Hello world")
  }

  @Test
  func `all musical note variants`() {
    let allNotes = "\u{2669}\u{266A}\u{266B}\u{266C}\u{266D}\u{266E}\u{266F}"
    #expect(TextSanitizer.sanitize(allNotes).isEmpty)
  }

  @Test
  func `multi word bracket annotation`() {
    let input = "Hello [background noise] world"
    #expect(TextSanitizer.sanitize(input) == "Hello world")
  }
}
