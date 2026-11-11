import Foundation

enum OperationPhase: String, Codable, Sendable {
  case requested, accepted, running, busy, completed, cancelled, failed, rejected
  var isTerminal: Bool {
    switch self {
    case .busy, .completed, .cancelled, .failed, .rejected: true
    case .requested, .accepted, .running: false
    }
  }
}

struct DictationDelivery: Codable, Equatable, Sendable {
  let schemaVersion: Int
  let resultID: UUID
  let sessionToken: String
  let destinationEpoch: UUID?
  let text: String

  func canInsert(requestToken: String?, currentEpoch: UUID) -> Bool {
    schemaVersion == 1 && requestToken == sessionToken
      && destinationEpoch == currentEpoch && !text.isEmpty
  }
}

enum OperationPolicy {
  // Terminal operations do not re-enter the active state on a late callback.
  static func mayTransition(from previous: OperationPhase?, to next: OperationPhase) -> Bool {
    guard let previous else {
      return next != .accepted && next != .running && next != .completed
    }
    if previous.isTerminal { return previous == next }
    switch next {
    case .requested: return previous == .requested
    case .accepted: return previous == .requested || previous == .accepted
    case .running: return true
    case .busy, .rejected: return previous == .requested || previous == .accepted
    case .completed, .cancelled, .failed: return true
    }
  }

  static func ownsCancellation(requested: String?, active: String?) -> Bool {
    guard let requested, !requested.isEmpty else { return false }
    return requested == active
  }

  static func canBeginTextWork(capturing: Bool, speechWorkers: Int) -> Bool {
    !capturing && speechWorkers == 0
  }

  static func sameDownload(
    task: Int?, session: String?, currentTask: Int?, currentSession: String?
  ) -> Bool {
    task != nil && task == currentTask && session == currentSession
  }
}

enum LiveDeliveryPolicy {
  static func accepts(
    token: String, requestToken: String?, currentToken: String?,
    revision: Int, lastRevision: Int,
    updatedAt: TimeInterval, now: TimeInterval,
    destinationEpoch: UUID?, currentEpoch: UUID
  ) -> Bool {
    guard UUID(uuidString: token) != nil,
          token == requestToken, token == currentToken,
          destinationEpoch == currentEpoch,
          revision > lastRevision, revision > 0,
          updatedAt.isFinite, now.isFinite else { return false }
    let age = now - updatedAt
    return age >= -5 && age <= 30
  }

  static func matchesField(
    ownedDocument: UUID?, currentDocument: UUID?,
    ownedEpoch: UUID?, currentEpoch: UUID,
    anchor: String, before: String?,
    expectedAfter: String?, after: String?,
    selectedText: String?
  ) -> Bool {
    guard let ownedDocument, let currentDocument,
          ownedDocument == currentDocument,
          ownedEpoch == currentEpoch,
          !anchor.isEmpty,
          before?.hasSuffix(anchor) == true,
          expectedAfter == after else { return false }
    return selectedText?.isEmpty ?? true
  }
}
