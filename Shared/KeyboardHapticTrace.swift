import Foundation

/// Diagnostic trace shared by app and keyboard. Deliberately stores no key,
/// text, clipboard, speech, app name or document context.
@MainActor
enum KeyboardHapticTrace {
  private static let countKey = "canto.haptics.requestCount"
  private static let eventsKey = "canto.haptics.requestTrace"
  private static var defaults: UserDefaults? { UserDefaults(suiteName: AppGroup.identifier) }

  static var total: Int { defaults?.integer(forKey: countKey) ?? 0 }
  static var events: [String] { defaults?.stringArray(forKey: eventsKey) ?? [] }

  static func record(technique: String, enabled: Bool, fullAccess: Bool) {
    guard let defaults else { return }
    let count = defaults.integer(forKey: countKey) + 1
    defaults.set(count, forKey: countKey)
    // Sample the first actions and then one in ten; never persist per-key content.
    guard count <= 8 || count.isMultiple(of: 10) else { return }
    let origin = Bundle.main.bundleURL.pathExtension == "appex" ? "extension" : "app"
    let event = "\(Int(Date().timeIntervalSince1970)) #\(count) \(origin) \(technique) requested=\(enabled) fullAccess=\(fullAccess)"
    var history = defaults.stringArray(forKey: eventsKey) ?? []
    history.append(event)
    if history.count > 40 { history.removeFirst(history.count - 40) }
    defaults.set(history, forKey: eventsKey)
  }

  static func clear() {
    defaults?.removeObject(forKey: countKey)
    defaults?.removeObject(forKey: eventsKey)
  }
}
