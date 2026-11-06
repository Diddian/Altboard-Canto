
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

struct LLMBridge: Sendable {

  @discardableResult
  static func writeRequest(_ request: LLMRequest) -> Bool {
    guard let url = requestFileURL else {
      FeatureDiagnostics.record(.bridge, .unavailable)
      return false
    }
    do {
      let data = try JSONEncoder().encode(request)
      try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
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
    guard let url = resultFileURL else {
      FeatureDiagnostics.record(.bridge, .unavailable)
      return false
    }
    do {
      let payload = LLMResult(requestID: requestID, text: text)
      try JSONEncoder().encode(payload).write(
        to: url, options: [.atomic, .completeFileProtectionUnlessOpen]
      )
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

  static func clearRequest() {
    guard let url = requestFileURL else { return }
    try? FileManager.default.removeItem(at: url)
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

