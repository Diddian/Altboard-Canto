import Foundation

enum DictationRequestPolicy {
  static func isCurrent(started: String?, current: String?, cancelled: Bool) -> Bool {
    guard let started, !started.isEmpty, !cancelled else { return false }
    return started == current
  }
}
