import Foundation
import Testing
@testable import Sayboard

@Suite("Pinned Heretic downloads")
struct HereticModelCatalogTests {
  @Test func entriesMatchTheirVariants() throws {
    for variant in [LLMModelVariant.hereticSmall, .hereticBalanced, .hereticLarge] {
      let entry = try #require(HereticModelCatalog.entry(for: variant))
      #expect(entry.url.host == "huggingface.co")
      #expect(entry.url.lastPathComponent == variant.ggufFileName)
      #expect(entry.url.pathComponents.contains { $0.count == 40 })
      #expect(entry.sha256.count == 64)
      #expect(entry.sha256.allSatisfy { $0.isHexDigit })
      #expect(entry.sizeBytes > 500_000_000)
      #expect(entry.peakDiskBytes == entry.sizeBytes)
      #expect(entry.isLoadableByThisBuild)
      #expect(Int64(variant.downloadSizeMB) * 1_000_000 >= entry.sizeBytes)
    }
    #expect(HereticModelCatalog.entry(for: .qwen35Small) == nil)
  }

  @Test func chineseInputOrOutputUsesAHereticDefault() throws {
    let name = "app.sayboard.tests.heretic." + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let settings = SharedSettings(defaults: defaults)
    settings.preferredSpokenLanguages = ["en", "de"]
    settings.voiceOutputTarget = .original
    #expect(settings.selectedLLMVariant == .qwen35Small)
    settings.voiceOutputTarget = .traditionalChinese
    #expect(settings.selectedLLMVariant == .hereticSmall)
    settings.voiceOutputTarget = .original
    settings.preferredSpokenLanguages = ["yue"]
    #expect(settings.selectedLLMVariant == .hereticSmall)
    settings.selectedLLMVariant = .gemma3OneQAT
    #expect(settings.selectedLLMVariant == .gemma3OneQAT)
  }

}
