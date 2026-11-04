
import Foundation

struct LLMRequest: Codable, Sendable {
  let text: String
  let action: LLMAction
  let customPromptId: UUID?
  let language: String?
}

struct LLMBridge: Sendable {

  @discardableResult
  static func writeRequest(_ request: LLMRequest) -> Bool {
    guard let url = requestFileURL else { return false }
    do {
      let data = try JSONEncoder().encode(request)
      try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
      return true
    } catch {
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
  static func writeResult(_ text: String) -> Bool {
    guard let url = resultFileURL else { return false }
    do {
      try Data(text.utf8).write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
      return true
    } catch {
      return false
    }
  }

  static func readResult() -> String? {
    guard let url = resultFileURL else { return nil }
    return try? String(contentsOf: url, encoding: .utf8)
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
