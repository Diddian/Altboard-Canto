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
