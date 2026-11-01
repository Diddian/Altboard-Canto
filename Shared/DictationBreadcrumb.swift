import Foundation

/// Release-safe diagnostic breadcrumbs that survive an app termination.
/// Never store audio, transcripts, prompts, names or model file paths.
enum DictationBreadcrumb {
  private static let storageKey = "canto.diagnostics.recentSteps"
  private static let maxSteps = 30

  static func record(_ stage: String) {
    let defaults = UserDefaults.standard
    let now = ISO8601DateFormatter().string(from: Date())
    var entries = defaults.stringArray(forKey: storageKey) ?? []
    entries.append("\(now)  \(stage)")
    if entries.count > maxSteps {
      entries.removeFirst(entries.count - maxSteps)
    }
    defaults.set(entries, forKey: storageKey)
    defaults.synchronize()
  }

  static var entries: [String] {
    UserDefaults.standard.stringArray(forKey: storageKey) ?? []
  }

  static var last: String {
    entries.last ?? "No dictation steps recorded yet"
  }

  static func clear() {
    UserDefaults.standard.removeObject(forKey: storageKey)
  }
}
