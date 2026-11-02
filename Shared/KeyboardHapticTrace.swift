import Foundation

/// App and extension each enqueue their diagnostic writes off the touch path.
/// The queue is serial per process; no text, keys, host IDs or audio are kept.
/// Persisting traces synchronously delayed haptics on every iPhone key-down.
enum KeyboardHapticTrace {
  private static let countKey = "canto.haptics.requestCount"
  private static let eventsKey = "canto.haptics.requestTrace"
  private static let queue = DispatchQueue(label: "app.altboard.keyboard-haptic-trace",
                                           qos: .utility)

  static var total: Int {
    UserDefaults(suiteName: AppGroup.identifier)?.integer(forKey: countKey) ?? 0
  }

  static var events: [String] {
    UserDefaults(suiteName: AppGroup.identifier)?.stringArray(forKey: eventsKey) ?? []
  }

  static func record(
    technique: String, enabled: Bool, fullAccess: Bool, outcome: String = "attempted"
  ) {
    let origin = Bundle.main.bundleURL.pathExtension == "appex" ? "extension" : "app"
    let timestamp = Int(Date().timeIntervalSince1970)
    queue.async {
      guard let defaults = UserDefaults(suiteName: AppGroup.identifier) else { return }
      let count = defaults.integer(forKey: countKey) + 1
      defaults.set(count, forKey: countKey)
      guard count <= 8 || count.isMultiple(of: 10) else { return }
      let event = "\(timestamp) #\(count) \(origin) \(technique) requested=\(enabled) fullAccess=\(fullAccess) outcome=\(outcome)"
      var history = defaults.stringArray(forKey: eventsKey) ?? []
      history.append(event)
      if history.count > 40 { history.removeFirst(history.count - 40) }
      defaults.set(history, forKey: eventsKey)
    }
  }

  static func clear() {
    queue.async {
      guard let defaults = UserDefaults(suiteName: AppGroup.identifier) else { return }
      defaults.removeObject(forKey: countKey)
      defaults.removeObject(forKey: eventsKey)
    }
  }
}
