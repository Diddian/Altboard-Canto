import Foundation

/// A local App Group presence flag, set only while Altboard's History test
/// TextField is focused in the foreground. Other host apps never set it.
enum HistoryKeyboardTestSession {
  private static let focusKey = "canto.historyKeyboardTest.focused"
  private static let timestampKey = "canto.historyKeyboardTest.focusedAt"
  private static let validity: TimeInterval = 3600

  static func setFocused(_ focused: Bool) {
    guard let defaults = AppGroup.sharedDefaults else { return }
    defaults.set(focused, forKey: focusKey)
    defaults.set(focused ? Date().timeIntervalSince1970 : 0, forKey: timestampKey)
  }

  static var isFocused: Bool {
    guard let defaults = AppGroup.sharedDefaults,
          defaults.bool(forKey: focusKey) else { return false }
    let at = defaults.double(forKey: timestampKey)
    let elapsed = Date().timeIntervalSince1970 - at
    return elapsed >= 0 && elapsed < validity
  }
}
