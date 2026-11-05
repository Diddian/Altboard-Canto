import Foundation
import Testing

@Suite("SharedSettings globe key cache")
struct SharedSettingsGlobeKeyTests {
  @Test func extraGlobeChoiceDefaultsOffAndPersists() throws {
    let suite = "test.altboard.globe." + UUID().uuidString
    guard let defaults = UserDefaults(suiteName: suite) else { return }
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = SharedSettings(defaults: defaults)
    #expect(!settings.keyboardShowGlobeKey)
    settings.keyboardShowGlobeKey = true
    #expect(SharedSettings(defaults: defaults).keyboardShowGlobeKey)
    settings.keyboardShowGlobeKey = false
    #expect(!SharedSettings(defaults: defaults).keyboardShowGlobeKey)
  }



  @Test
  func `a keyboard that never read the flag assumes it needs the globe`() throws {
    let suiteName = Self.uniqueSuiteName()
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { Self.cleanup(suiteName: suiteName) }

    #expect(SharedSettings(defaults: defaults).needsInputModeSwitchKey)
  }

  @Test
  func `the app reads the same assumption before the keyboard stores a value`() throws {
    let suiteName = Self.uniqueSuiteName()
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { Self.cleanup(suiteName: suiteName) }
    _ = SharedSettings(defaults: defaults)

    #expect(defaults.bool(forKey: SharedKey.needsInputModeSwitchKey))
  }

  @Test
  func `a stored false is kept`() throws {
    let suiteName = Self.uniqueSuiteName()
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { Self.cleanup(suiteName: suiteName) }

    SharedSettings(defaults: defaults).needsInputModeSwitchKey = false

    #expect(!SharedSettings(defaults: defaults).needsInputModeSwitchKey)
  }

  private static func uniqueSuiteName() -> String {
    "app.sayboard.tests.\(UUID().uuidString)"
  }

  private static func cleanup(suiteName: String) {
    UserDefaults().removePersistentDomain(forName: suiteName)
  }
}
