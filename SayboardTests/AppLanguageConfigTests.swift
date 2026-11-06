import Testing

private let appLanguageCodes = [
  "bg",
  "cs",
  "da",
  "de",
  "el",
  "en",
  "es",
  "et",
  "fi",
  "fr",
  "hi",
  "hr",
  "hu",
  "it",
  "ja",
  "ko",
  "lt",
  "lv",
  "nl",
  "no",
  "pl",
  "pt",
  "ro",
  "ru",
  "sk",
  "sl",
  "sv",
  "tr",
  "uk",
  "zh-Hans",
  "zh-Hant",
]

@Suite("AppLanguageConfig.resolveLanguage")
struct AppLanguageConfigTests {

  @Test
  func `russian locale`() {
    let result = AppLanguageConfig.resolveLanguage(from: ["ru-RU"])
    #expect(result == "ru")
  }

  @Test
  func `english US`() {
    let result = AppLanguageConfig.resolveLanguage(from: ["en-US"])
    #expect(result == "en")
  }

  @Test
  func `english GB`() {
    let result = AppLanguageConfig.resolveLanguage(from: ["en-GB"])
    #expect(result == "en")
  }

  @Test
  func `unsupported language falls back to english`() {
    let result = AppLanguageConfig.resolveLanguage(from: ["sw-KE"])
    #expect(result == "en")
  }

  @Test
  func `empty array falls back to english`() {
    let result = AppLanguageConfig.resolveLanguage(from: [])
    #expect(result == "en")
  }

  @Test
  func `only first language is checked`() {
    let result = AppLanguageConfig.resolveLanguage(from: ["sw-KE", "ru-RU"])
    #expect(result == "en")
  }

  @Test
  func `bare language code`() {
    let result = AppLanguageConfig.resolveLanguage(from: ["ru"])
    #expect(result == "ru")
  }

  @Test
  func `japanese resolves to ja`() {
    let result = AppLanguageConfig.resolveLanguage(from: ["ja-JP"])
    #expect(result == "ja")
  }

  @Test
  func `german resolves to de`() {
    let result = AppLanguageConfig.resolveLanguage(from: ["de-DE"])
    #expect(result == "de")
  }

  @Test
  func `chinese simplified resolves to zh Hans`() {
    let result = AppLanguageConfig.resolveLanguage(from: ["zh-Hans-CN"])
    #expect(result == "zh-Hans")
  }

  @Test
  func `hong kong chinese defaults to traditional`() {
    #expect(AppLanguageConfig.resolveLanguage(from: ["zh-HK"]) == "zh-Hant")
    #expect(AppLanguageConfig.resolveLanguage(from: ["zh-TW"]) == "zh-Hant")
    #expect(AppLanguageConfig.resolveLanguage(from: ["yue-HK"]) == "zh-Hant")
  }

  @Test
  func `explicit chinese scripts remain distinct`() {
    #expect(AppLanguageConfig.resolveLanguage(from: ["zh-Hant-HK"]) == "zh-Hant")
    #expect(AppLanguageConfig.resolveLanguage(from: ["zh-Hans-CN"]) == "zh-Hans")
    #expect(AppLanguageConfig.migratedStoredLanguage("zh") == "zh-Hans")
    #expect(AppLanguageConfig.migratedStoredLanguage("zh-Hant") == "zh-Hant")
  }

  @Test
  func `ukrainian resolves to uk`() {
    let result = AppLanguageConfig.resolveLanguage(from: ["uk-UA"])
    #expect(result == "uk")
  }

  @Test
  func `norwegian bokmal resolves to no`() {
    let result = AppLanguageConfig.resolveLanguage(from: ["nb-NO"])
    #expect(result == "no")
  }

  @Test
  func `bare nb resolves to no`() {
    let result = AppLanguageConfig.resolveLanguage(from: ["nb"])
    #expect(result == "no")
  }

  @Test
  func `legacy no identifier resolves to no`() {
    let result = AppLanguageConfig.resolveLanguage(from: ["no"])
    #expect(result == "no")
  }

  @Test
  func `norwegian nynorsk resolves to no`() {
    let result = AppLanguageConfig.resolveLanguage(from: ["nn-NO"])
    #expect(result == "no")
  }

  @Test(arguments: appLanguageCodes)
  func `every app language code resolves to itself`(code: String) {
    #expect(AppLanguageConfig.resolveLanguage(from: [code]) == code)
  }
}
