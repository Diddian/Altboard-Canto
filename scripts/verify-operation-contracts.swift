import Foundation

enum LLMAction: String, Codable, Sendable { case rewrite, translate }
enum FeatureDiagnostics {
  enum Area { case bridge }
  enum Event { case unavailable, queued, failed }
  static func record(_ area: Area, _ event: Event,
                     operationID: String? = nil, phase: OperationPhase? = nil) {}
}
enum DiagnosticLog { static func write(_ message: String) {} }
enum AppGroup {
  static let containerURL: URL? = {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("operation-contracts-" + UUID().uuidString)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }()
}
struct SharedSettings {
  var dictationSessionToken: String? { "00000000-0000-0000-0000-000000000001" }
  var dictationDestinationEpoch: UUID? { UUID(uuidString: "00000000-0000-0000-0000-000000000002") }
}
enum DarwinNotificationName {
  static let transcriptionReady = "test.altboard.transcriptionReady"
  static let voiceProgressUpdated = "test.altboard.voiceProgressUpdated"
}

@main
enum VerifyOperationContracts {
  static func main() throws {
    defer { if let url = AppGroup.containerURL { try? FileManager.default.removeItem(at: url) } }
    let epoch = UUID()
    let delivery = DictationDelivery(schemaVersion: 1, resultID: UUID(),
      sessionToken: "request-a", destinationEpoch: epoch, text: "sample")
    precondition(delivery.canInsert(requestToken: "request-a", currentEpoch: epoch))
    precondition(!delivery.canInsert(requestToken: "request-b", currentEpoch: epoch))
    precondition(!delivery.canInsert(requestToken: "request-a", currentEpoch: UUID()))
    precondition(!delivery.canInsert(requestToken: nil, currentEpoch: epoch))
    let unknown = DictationDelivery(schemaVersion: 1, resultID: UUID(),
      sessionToken: "request-a", destinationEpoch: nil, text: "sample")
    precondition(!unknown.canInsert(requestToken: "request-a", currentEpoch: epoch))
    precondition(OperationPolicy.ownsCancellation(requested: "a", active: "a"))
    precondition(!OperationPolicy.ownsCancellation(requested: "a", active: "b"))
    precondition(!OperationPolicy.ownsCancellation(requested: nil, active: nil))
    precondition(!OperationPolicy.ownsCancellation(requested: "", active: ""))
    for capturing in [true, false] {
      for workers in 0...3 {
        precondition(OperationPolicy.canBeginTextWork(capturing: capturing, speechWorkers: workers)
          == (!capturing && workers == 0))
      }
    }
    precondition(OperationPolicy.sameDownload(task: 1, session: "one", currentTask: 1, currentSession: "one"))
    precondition(!OperationPolicy.sameDownload(task: 1, session: "one", currentTask: 2, currentSession: "one"))
    precondition(!OperationPolicy.sameDownload(task: 1, session: "one", currentTask: 1, currentSession: "two"))
    precondition(!OperationPolicy.sameDownload(task: nil, session: nil, currentTask: nil, currentSession: nil))

    let a = LLMRequest(text: "sample", action: .rewrite, customPromptId: nil, language: "en")
    let b = LLMRequest(text: "second", action: .rewrite, customPromptId: nil, language: "en")
    precondition(LLMBridge.writeRequest(a))
    precondition(LLMBridge.readStatus(matching: a.requestID)?.phase == .requested)
    LLMBridge.writeStatus(.accepted, requestID: a.requestID)
    LLMBridge.writeStatus(.busy, requestID: b.requestID)
    precondition(LLMBridge.readStatus(matching: a.requestID)?.phase == .accepted)
    precondition(LLMBridge.readStatus(matching: b.requestID)?.phase == .busy)
    LLMBridge.clearRequest(matching: b.requestID)
    precondition(LLMBridge.readRequest()?.requestID == a.requestID)
    precondition(LLMBridge.writeResult("result", requestID: a.requestID))
    precondition(LLMBridge.readStatus(matching: a.requestID)?.phase == .completed)
    LLMBridge.clearResult(matching: b.requestID)
    precondition(LLMBridge.readResult(matching: a.requestID) == "result")
    LLMBridge.clearResult(matching: a.requestID)
    precondition(!LLMBridge.hasResult())
    LLMBridge.clearRequest(matching: a.requestID)
    precondition(LLMBridge.readRequest() == nil)

    precondition(TranscriptionBridge.writeTranscription("synthetic final text"))
    let pending = TranscriptionBridge.readDelivery()!
    TranscriptionBridge.acknowledgeDelivery(UUID())
    precondition(TranscriptionBridge.readDelivery()?.resultID == pending.resultID)
    precondition(TranscriptionBridge.writeTranscription("a newer synthetic result"))
    TranscriptionBridge.acknowledgeDelivery(pending.resultID)
    let newer = TranscriptionBridge.readDelivery()!
    precondition(newer.resultID != pending.resultID)
    precondition(newer.text == "a newer synthetic result")
    TranscriptionBridge.acknowledgeDelivery(newer.resultID)
    precondition(TranscriptionBridge.readDelivery() == nil)
    TranscriptionBridge.requestCancellation(for: "00000000-0000-0000-0000-000000000003")
    precondition(TranscriptionBridge.cancellationToken() == "00000000-0000-0000-0000-000000000003")

    let legacy = ConversationTurn(id: UUID(), speaker: .me,
      audioFileName: UUID().uuidString + ".caf", duration: 25.1, targetCode: "",
      sourceText: "sample", translatedText: nil, detectedLanguageCode: "en", status: .processing)
    let oldData = try JSONEncoder().encode([legacy])
    let oldTurns = try JSONDecoder().decode([ConversationTurn].self, from: oldData)
    precondition(oldTurns[0].status == .processing)
    let draft = ConversationDraft(schemaVersion: 1, turns: oldTurns)
    let restored = try JSONDecoder().decode(ConversationDraft.self, from: JSONEncoder().encode(draft))
    precondition(restored.turns[0].sourceText == "sample")
    let future = try JSONDecoder().decode(ConversationTurnState.self,
      from: Data("\"future-state\"".utf8))
    precondition(future == .interrupted)
    precondition(ConversationTurnPolicy.maximumRecoverySeconds > ConversationTurnPolicy.maximumCaptureSeconds)
    precondition(OperationPhase.busy.isTerminal && !OperationPhase.accepted.isTerminal)
    print("Operation identity, bridge acknowledgement, resource guards and legacy recovery: PASS")
  }
}
