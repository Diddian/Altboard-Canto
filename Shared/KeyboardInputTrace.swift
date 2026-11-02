import Foundation

/// Bounded input-action breadcrumbs. No text, keystroke, cursor position,
/// host bundle ID, transcript, or candidate text is saved.
@MainActor
enum KeyboardInputTrace {
  enum Action: String {
    case spaceTouched
    case spaceCommitted
    case latinKept
    case latinSuggestionChosen
    case candidateChosen
    case syllableDeleted
    case ordinaryDelete
    case keyboardDismissRequested
  }

  private static let key = "canto.keyboard.inputTrace"
  private static var defaults: UserDefaults? { UserDefaults(suiteName: AppGroup.identifier) }
  static var events: [String] { defaults?.stringArray(forKey: key) ?? [] }

  static func record(_ action: Action) {
    guard let defaults else { return }
    var items = defaults.stringArray(forKey: key) ?? []
    items.append("\(Int(Date().timeIntervalSince1970)) \(action.rawValue)")
    if items.count > 24 { items.removeFirst(items.count - 24) }
    defaults.set(items, forKey: key)
  }

  static func clear() { defaults?.removeObject(forKey: key) }
}
