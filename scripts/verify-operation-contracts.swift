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
    // A second keyboard cannot replace another pending request.
    precondition(!LLMBridge.writeRequest(b))
    precondition(LLMBridge.readRequest()?.requestID == a.requestID)
    precondition(LLMBridge.writeStatus(.accepted, requestID: a.requestID))
    // A replayed Darwin notification must not turn the active job into busy.
    precondition(!LLMBridge.writeStatus(.busy, requestID: a.requestID))
    LLMBridge.clearRequest(matching: a.requestID)
    precondition(LLMBridge.readRequest()?.requestID == a.requestID)
    LLMBridge.writeStatus(.busy, requestID: b.requestID)
    precondition(LLMBridge.readStatus(matching: a.requestID)?.phase == .accepted)
    precondition(LLMBridge.readStatus(matching: b.requestID)?.phase == .busy)
    LLMBridge.clearRequest(matching: b.requestID)
    precondition(LLMBridge.readRequest()?.requestID == a.requestID)
    precondition(LLMBridge.writeResult("result", requestID: a.requestID))
    precondition(LLMBridge.readStatus(matching: a.requestID)?.phase == .completed)
    LLMBridge.clearResult(matching: b.requestID)
    precondition(LLMBridge.readResult(matching: a.requestID) == "result")
    precondition(!LLMBridge.writeRequest(b))
    LLMBridge.clearResult(matching: a.requestID)
    precondition(!LLMBridge.hasResult())
    LLMBridge.clearRequest(matching: a.requestID)
    precondition(LLMBridge.readRequest() == nil)
    let nextRequest = LLMRequest(text: "next", action: .rewrite,
      customPromptId: nil, language: "en")
    precondition(LLMBridge.writeRequest(nextRequest))
    precondition(LLMBridge.readRequest()?.requestID == nextRequest.requestID)
    // Preserve unreadable pending data rather than overwriting it.
    precondition(LLMBridge.writeStatus(.cancelled, requestID: nextRequest.requestID))
    LLMBridge.clearRequest(matching: nextRequest.requestID)
    let malformedURL = AppGroup.containerURL!.appendingPathComponent("llm_request.json")
    try Data("malformed-pending-request".utf8).write(to: malformedURL, options: .atomic)
    let blocked = LLMRequest(text: "must not overwrite", action: .rewrite,
      customPromptId: nil, language: "de")
    precondition(!LLMBridge.writeRequest(blocked))
    let preservedPendingBytes = try Data(contentsOf: malformedURL)
    precondition(preservedPendingBytes == Data("malformed-pending-request".utf8))
    try FileManager.default.removeItem(at: malformedURL)

    precondition(TranscriptionBridge.writeTranscription("synthetic final text"))
    let pending = TranscriptionBridge.readDelivery()!
    let requestToken = SharedSettings().dictationSessionToken
    let requestEpoch = SharedSettings().dictationDestinationEpoch
    precondition(TranscriptionBridge.readDelivery(matching: requestToken,
      destinationEpoch: requestEpoch)?.resultID == pending.resultID)
    precondition(TranscriptionBridge.readDelivery(matching: UUID().uuidString,
      destinationEpoch: requestEpoch) == nil)
    precondition(TranscriptionBridge.readDelivery(matching: requestToken,
      destinationEpoch: UUID()) == nil)
    precondition(TranscriptionBridge.readDelivery(matching: nil,
      destinationEpoch: requestEpoch) == nil)
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
    precondition(!OperationPolicy.mayTransition(from: .accepted, to: .busy))
    precondition(LiveFinalReconciliation.plan(
      partial: "hello", final: "hello", marked: " hello",
      prefix: " ", before: " hello"
    ) == .unchanged)
    precondition(LiveFinalReconciliation.plan(
      partial: "hello", final: "hello world", marked: " hello",
      prefix: " ", before: " hello"
    ) == .append(" world"))
    precondition(LiveFinalReconciliation.plan(
      partial: "goood", final: "good", marked: " goood",
      prefix: " ", before: " goood"
    ) == .replace(" good"))
    precondition(LiveFinalReconciliation.plan(
      partial: "goood", final: "good", marked: " goood",
      prefix: " ", before: "truncated ood"
    ) == .review)
    precondition(OperationPolicy.mayTransition(from: nil, to: .requested))
    precondition(OperationPolicy.mayTransition(from: .requested, to: .accepted))
    precondition(OperationPolicy.mayTransition(from: .accepted, to: .completed))
    precondition(!OperationPolicy.mayTransition(from: .completed, to: .failed))
    precondition(!OperationPolicy.mayTransition(from: .cancelled, to: .running))
    precondition(!OperationPolicy.mayTransition(from: nil, to: .completed))
    let liveToken = UUID().uuidString
    let liveEpoch = UUID()
    precondition(LiveDeliveryPolicy.accepts(
      token: liveToken, requestToken: liveToken, currentToken: liveToken,
      revision: 2, lastRevision: 1, updatedAt: 99, now: 100,
      destinationEpoch: liveEpoch, currentEpoch: liveEpoch
    ))
    precondition(!LiveDeliveryPolicy.accepts(
      token: liveToken, requestToken: liveToken, currentToken: liveToken,
      revision: 2, lastRevision: 2, updatedAt: 99, now: 100,
      destinationEpoch: liveEpoch, currentEpoch: liveEpoch
    ))
    precondition(!LiveDeliveryPolicy.accepts(
      token: liveToken, requestToken: liveToken, currentToken: liveToken,
      revision: 3, lastRevision: 2, updatedAt: 10, now: 100,
      destinationEpoch: liveEpoch, currentEpoch: liveEpoch
    ))
    let document = UUID()
    precondition(LiveDeliveryPolicy.matchesField(
      ownedDocument: document, currentDocument: document,
      ownedEpoch: liveEpoch, currentEpoch: liveEpoch,
      anchor: "sample", before: "a sample",
      expectedAfter: " tail", after: " tail", selectedText: nil
    ))
    precondition(!LiveDeliveryPolicy.matchesField(
      ownedDocument: document, currentDocument: UUID(),
      ownedEpoch: liveEpoch, currentEpoch: liveEpoch,
      anchor: "sample", before: "a sample",
      expectedAfter: " tail", after: " tail", selectedText: nil
    ))
    precondition(!LiveDeliveryPolicy.matchesField(
      ownedDocument: document, currentDocument: document,
      ownedEpoch: liveEpoch, currentEpoch: UUID(),
      anchor: "sample", before: "a sample",
      expectedAfter: " tail", after: " tail", selectedText: nil
    ))
    precondition(!LiveDeliveryPolicy.matchesField(
      ownedDocument: document, currentDocument: document,
      ownedEpoch: liveEpoch, currentEpoch: liveEpoch,
      anchor: "sample", before: "a sample",
      expectedAfter: " tail", after: "changed", selectedText: nil
    ))
    LLMBridge.clearStatus(matching: a.requestID)
    precondition(LLMBridge.readStatus(matching: a.requestID)?.phase == .completed)
    precondition(!LLMBridge.writeStatus(.failed, requestID: a.requestID))
    precondition(!LLMBridge.writeResult("late", requestID: a.requestID))
    print("Operation identity, bridge acknowledgement, resource guards and legacy recovery: PASS")
  }
}
