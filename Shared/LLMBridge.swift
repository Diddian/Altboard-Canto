
import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

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
    self.withBridgeLock { self.writeStatusUnlocked(phase, requestID: requestID) } ?? false
  }

  private static func writeStatusUnlocked(_ phase: OperationPhase, requestID: UUID) -> Bool {
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
        // Only remove terminal markers; an active request has no replacement.
        for file in sorted.dropFirst(64) {
          if let bytes = try? Data(contentsOf: file),
             let old = try? JSONDecoder().decode(LLMJobStatus.self, from: bytes),
             old.phase.isTerminal {
            try? FileManager.default.removeItem(at: file)
          }
        }
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
    // Only one request can own the legacy single-slot bridge at a time.
    // A second keyboard must never erase another keyboard's pending work.
    return self.withBridgeLock {
      // A corrupt/unreadable request is still someone else's pending data.
      guard !FileManager.default.fileExists(atPath: url.path),
            !self.hasResult() else { return false }
      do {
        let data = try JSONEncoder().encode(request)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
        guard self.writeStatusUnlocked(.requested, requestID: request.requestID) else {
          try? FileManager.default.removeItem(at: url)
          return false
        }
        FeatureDiagnostics.record(.bridge, .queued)
        return true
      } catch {
        FeatureDiagnostics.record(.bridge, .failed)
        return false
      }
    } ?? false
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
    guard let url = resultFileURL else {
      FeatureDiagnostics.record(.bridge, .unavailable)
      return false
    }
    // Serialize terminal publication with cancellation and request handoff.
    return self.withBridgeLock {
      guard let phase = self.readStatus(matching: requestID)?.phase,
            phase == .accepted || phase == .running,
            !self.hasResult() else { return false }
      do {
        let payload = LLMResult(requestID: requestID, text: text)
        try JSONEncoder().encode(payload).write(
          to: url, options: [.atomic, .completeFileProtectionUnlessOpen]
        )
        guard self.writeStatusUnlocked(.completed, requestID: requestID) else {
          try? FileManager.default.removeItem(at: url)
          return false
        }
        FeatureDiagnostics.record(.bridge, .queued)
        return true
      } catch {
        FeatureDiagnostics.record(.bridge, .failed)
        return false
      }
    } ?? false
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
    _ = self.withBridgeLock {
      guard self.readRequest()?.requestID == requestID else { return false }
      // Duplicate Darwin delivery cannot clear an accepted in-flight job.
      if let phase = self.readStatus(matching: requestID)?.phase,
         !phase.isTerminal { return false }
      guard let url = requestFileURL else { return false }
      try? FileManager.default.removeItem(at: url)
      return true
    }
  }

  static func clearRequest() {
    guard let request = self.readRequest() else { return }
    self.clearRequest(matching: request.requestID)
  }

  static func clearResult(matching requestID: UUID) {
    _ = self.withBridgeLock {
      guard self.readResult(matching: requestID) != nil,
            let url = resultFileURL else { return false }
      try? FileManager.default.removeItem(at: url)
      return true
    }
  }

  static func clearResult() {
    // Recover the recorded owner; do not blindly erase another job's result.
    guard let url = resultFileURL,
          let data = try? Data(contentsOf: url),
          let result = try? JSONDecoder().decode(LLMResult.self, from: data)
    else { return }
    self.clearResult(matching: result.requestID)
  }

  /// The single-slot App Group bridge requires a cross-process lease.
  /// The file carries no user content. Acquire it only for bounded JSON IO.
  private static func withBridgeLock<T>(_ operation: () -> T) -> T? {
    guard let root = AppGroup.containerURL else { return nil }
    let path = root.appendingPathComponent("llm-bridge-v1.lock").path
    let fd = open(path, O_CREAT | O_RDWR, mode_t(0o600))
    guard fd >= 0 else { return nil }
    defer {
      _ = flock(fd, LOCK_UN)
      _ = close(fd)
    }
    guard flock(fd, LOCK_EX) == 0 else { return nil }
    return operation()
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


