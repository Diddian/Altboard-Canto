import Foundation
import os
import Testing

@Suite("SharedSettings registered defaults")
struct SharedSettingsDefaultsTests {

  @Test
  func `building SharedSettings posts no defaults change`() throws {
    let suiteName = Self.uniqueSuiteName()
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { Self.cleanup(suiteName: suiteName) }
    let posts = OSAllocatedUnfairLock(initialState: 0)
    let observer = NotificationCenter.default.addObserver(
      forName: UserDefaults.didChangeNotification,
      object: defaults,
      queue: nil,
    ) { _ in
      posts.withLock { $0 += 1 }
    }
    defer { NotificationCenter.default.removeObserver(observer) }

    _ = SharedSettings(defaults: defaults)
    _ = SharedSettings(defaults: defaults)

    #expect(posts.withLock { $0 } == 0)
  }

  @Test
  func `a fresh suite reads the registered defaults`() throws {
    let suiteName = Self.uniqueSuiteName()
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { Self.cleanup(suiteName: suiteName) }
    _ = SharedSettings()

    let settings = SharedSettings(defaults: defaults)

    #expect(settings.keyboardHeightScale == 0.92)
    #expect(settings.keyboardHapticsEnabled)
    #expect(settings.periodShortcutEnabled)
  }

  @Test
  func keyboardHeightIsClampedAndPersists() throws {
    let suiteName = Self.uniqueSuiteName()
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { Self.cleanup(suiteName: suiteName) }
    let settings = SharedSettings(defaults: defaults)
    settings.keyboardHeightScale = 0.68
    #expect(settings.keyboardHeightScale == 0.70)
    settings.keyboardHeightScale = 1.20
    #expect(settings.keyboardHeightScale == 1.10)
    settings.keyboardHeightScale = 0.88
    #expect(SharedSettings(defaults: defaults).keyboardHeightScale == 0.88)
  }

  private static func uniqueSuiteName() -> String {
    "app.sayboard.tests.\(UUID().uuidString)"
  }

  private static func cleanup(suiteName: String) {
    UserDefaults().removePersistentDomain(forName: suiteName)
  }
}
