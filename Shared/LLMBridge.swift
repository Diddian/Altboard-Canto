
import Foundation

struct LLMRequest: Codable, Sendable {
  var requestID = UUID()
  let text: String
  let action: LLMAction
  let customPromptId: UUID?
  let language: String?
  var translationTarget: String? = nil
  var customTranslationLanguage: String? = nil
}

struct LLMResult: Codable, Sendable {
  let requestID: UUID
  let text: String
}

struct LLMJobStatus: Codable, Sendable {
  let schemaVersion: Int
  let requestID: UUID
  let phase: OperationPhase
}

struct LLMBridge: Sendable {

  @discardableResult
  static func writeStatus(_ phase: OperationPhase, requestID: UUID) -> Bool {
    guard let folder = AppGroup.containerURL?.appendingPathComponent("text-job-status", isDirectory: true)
    else { return false }
    guard OperationPolicy.mayTransition(
      from: self.readStatus(matching: requestID)?.phase, to: phase
    ) else { return false }
    do {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      let status = LLMJobStatus(schemaVersion: 1, requestID: requestID, phase: phase)
      try JSONEncoder().encode(status).write(
        to: folder.appendingPathComponent(requestID.uuidString + ".json"),
        options: [.atomic, .completeFileProtectionUnlessOpen]
      )
      let files = (try? FileManager.default.contentsOfDirectory(
        at: folder, includingPropertiesForKeys: [.contentModificationDateKey]
      )) ?? []
      if files.count > 64 {
        let sorted = files.sorted {
          ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
            > ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
        }
        for file in sorted.dropFirst(64) { try? FileManager.default.removeItem(at: file) }
      }
      return true
    } catch {
      FeatureDiagnostics.record(.bridge, .failed)
      return false
    }
  }

  static func readStatus(matching requestID: UUID) -> LLMJobStatus? {
    guard let url = AppGroup.containerURL?
      .appendingPathComponent("text-job-status", isDirectory: true)
      .appendingPathComponent(requestID.uuidString + ".json"),
      let bytes = try? Data(contentsOf: url),
      let status = try? JSONDecoder().decode(LLMJobStatus.self, from: bytes),
      status.schemaVersion == 1, status.requestID == requestID else { return nil }
    return status
  }

  static func clearStatus(matching requestID: UUID) {
    // Retain the bounded terminal marker so the host defer cannot report
    // an already delivered completion as failure after keyboard acknowledgement.
    if self.readStatus(matching: requestID)?.phase.isTerminal == true { return }
    guard let url = AppGroup.containerURL?
      .appendingPathComponent("text-job-status", isDirectory: true)
      .appendingPathComponent(requestID.uuidString + ".json") else { return }
    try? FileManager.default.removeItem(at: url)
  }

  @discardableResult
  static func writeRequest(_ request: LLMRequest) -> Bool {
    guard let url = requestFileURL else {
      FeatureDiagnostics.record(.bridge, .unavailable)
      return false
    }
    do {
      let data = try JSONEncoder().encode(request)
      try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
      guard self.writeStatus(.requested, requestID: request.requestID) else {
        self.clearRequest(matching: request.requestID)
        return false
      }
      FeatureDiagnostics.record(.bridge, .queued)
      return true
    } catch {
      FeatureDiagnostics.record(.bridge, .failed)
      return false
    }
  }

  static func readRequest() -> LLMRequest? {
    guard let url = requestFileURL else { return nil }
    guard let data = try? Data(contentsOf: url) else {
      return nil
    }
    return try? JSONDecoder().decode(LLMRequest.self, from: data)
  }

  @discardableResult
  static func writeResult(_ text: String, requestID: UUID) -> Bool {
    // Ignore late or repeated results after a terminal outcome.
    guard let phase = self.readStatus(matching: requestID)?.phase,
          phase != .completed,
          OperationPolicy.mayTransition(from: phase, to: .completed) else { return false }
    guard let url = resultFileURL else {
      FeatureDiagnostics.record(.bridge, .unavailable)
      return false
    }
    do {
      let payload = LLMResult(requestID: requestID, text: text)
      try JSONEncoder().encode(payload).write(
        to: url, options: [.atomic, .completeFileProtectionUnlessOpen]
      )
      guard self.writeStatus(.completed, requestID: requestID) else {
        self.clearResult(matching: requestID)
        return false
      }
      FeatureDiagnostics.record(.bridge, .queued)
      return true
    } catch {
      FeatureDiagnostics.record(.bridge, .failed)
      return false
    }
  }

  static func readResult(matching requestID: UUID?) -> String? {
    guard let requestID, let url = resultFileURL,
          let data = try? Data(contentsOf: url),
          let payload = try? JSONDecoder().decode(LLMResult.self, from: data),
          payload.requestID == requestID else { return nil }
    return payload.text
  }

  static func hasResult() -> Bool {
    guard let url = resultFileURL else { return false }
    return FileManager.default.fileExists(atPath: url.path)
  }

  static func clearRequest(matching requestID: UUID) {
    guard self.readRequest()?.requestID == requestID else { return }
    self.clearRequest()
  }

  static func clearRequest() {
    guard let url = requestFileURL else { return }
    try? FileManager.default.removeItem(at: url)
  }

  static func clearResult(matching requestID: UUID) {
    guard self.readResult(matching: requestID) != nil else { return }
    self.clearResult()
  }

  static func clearResult() {
    guard let url = resultFileURL else { return }
    try? FileManager.default.removeItem(at: url)
  }

  private static let requestFileName = "llm_request.json"
  private static let resultFileName = "llm_result.txt"

  private static var requestFileURL: URL? {
    AppGroup.containerURL?.appendingPathComponent(requestFileName)
  }

  private static var resultFileURL: URL? {
    AppGroup.containerURL?.appendingPathComponent(resultFileName)
  }
}


