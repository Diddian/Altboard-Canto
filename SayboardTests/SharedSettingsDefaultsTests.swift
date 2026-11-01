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

  @Test
  func keyboardModesRetainLegacyIdentifiers() throws {
    let suiteName = Self.uniqueSuiteName()
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { Self.cleanup(suiteName: suiteName) }
    let settings = SharedSettings(defaults: defaults)
    defaults.set("standard", forKey: SharedKey.keyboardKind)
    #expect(settings.keyboardKind == .standard)
    defaults.set("extended", forKey: SharedKey.keyboardKind)
    #expect(settings.keyboardKind == .extended)
    settings.keyboardKind = .alphabetic
    #expect(SharedSettings(defaults: defaults).keyboardKind == .alphabetic)
  }

  @Test
  func letterLayoutDefaultsToQWERTZAndCanUseQWERTY() throws {
    let suiteName = Self.uniqueSuiteName()
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { Self.cleanup(suiteName: suiteName) }
    let settings = SharedSettings(defaults: defaults)
    #expect(settings.keyboardLetterArrangement == .qwertz)
    #expect(LetterKeyArrangement.qwertz.rows[0][5] == "Z")
    #expect(LetterKeyArrangement.qwertz.rows[2][0] == "Y")
    #expect(LetterKeyArrangement.qwerty.rows[0][5] == "Y")
    #expect(LetterKeyArrangement.qwerty.rows[2][0] == "Z")
    settings.keyboardLetterArrangement = .qwerty
    #expect(SharedSettings(defaults: defaults).keyboardLetterArrangement == .qwerty)
    #expect(LetterKeyArrangement.qwerty.rows.flatMap { $0 }.count == 26)
    #expect(LetterKeyArrangement.qwertz.rows.flatMap { $0 }.count == 26)
  }

  @Test
  func hapticStrengthIsClampedAndPersists() throws {
    let suiteName = Self.uniqueSuiteName()
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { Self.cleanup(suiteName: suiteName) }
    let settings = SharedSettings(defaults: defaults)
    #expect(settings.keyboardHapticStrength == 0.6)
    settings.keyboardHapticStrength = 0.01
    #expect(settings.keyboardHapticStrength == 0.15)
    settings.keyboardHapticStrength = 1.5
    #expect(settings.keyboardHapticStrength == 1.0)
    settings.keyboardHapticStrength = 0.45
    #expect(SharedSettings(defaults: defaults).keyboardHapticStrength == 0.45)
  }

  private static func uniqueSuiteName() -> String {
    "app.sayboard.tests.\(UUID().uuidString)"
  }

  private static func cleanup(suiteName: String) {
    UserDefaults().removePersistentDomain(forName: suiteName)
  }
}
