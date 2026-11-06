import Foundation
import Testing

@Suite("SharedSettings globe key cache")
struct SharedSettingsGlobeKeyTests {

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
