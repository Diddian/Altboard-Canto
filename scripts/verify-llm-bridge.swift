import Foundation

// The bridge test is standalone: no host app or model is started.
enum LLMAction: String, Codable, Sendable {
  case rewrite
  case translate
}

enum AppGroup {
  static let containerURL: URL? = {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("altboard-llm-bridge-" + UUID().uuidString)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }()
}

@main
enum VerifyLLMBridge {
  static func main() {
    defer {
      if let url = AppGroup.containerURL {
        try? FileManager.default.removeItem(at: url)
      }
    }

    let request = LLMRequest(
      text: "sample text", action: .rewrite,
      customPromptId: nil, language: "en"
    )
    let translation = LLMRequest(
      text: "Hello", action: .translate, customPromptId: nil, language: "en",
      translationTarget: "german", customTranslationLanguage: ""
    )
    precondition(LLMBridge.writeRequest(translation))
    precondition(LLMBridge.readRequest()?.translationTarget == "german")
    let oldJSON = """
      {"requestID":"00000000-0000-0000-0000-000000000001","text":"old request","action":"rewrite","language":"en"}
      """
    let old = try! JSONDecoder().decode(LLMRequest.self, from: Data(oldJSON.utf8))
    precondition(old.translationTarget == nil)
    LLMBridge.clearResult()
    LLMBridge.clearRequest()
    precondition(!LLMBridge.hasResult())
    precondition(LLMBridge.writeRequest(request))
    let restored = LLMBridge.readRequest()
    precondition(restored?.requestID == request.requestID)
    precondition(restored?.text == request.text)
    precondition(LLMBridge.writeResult("rewritten", requestID: request.requestID))
    precondition(LLMBridge.hasResult())
    precondition(LLMBridge.readResult(matching: request.requestID) == "rewritten")
    precondition(LLMBridge.readResult(matching: UUID()) == nil)
    precondition(LLMBridge.readResult(matching: nil) == nil)
    LLMBridge.clearResult()
    LLMBridge.clearRequest()
    precondition(!LLMBridge.hasResult())
    precondition(LLMBridge.readRequest() == nil)
    print("LLM bridge request identity and stale-result rejection verified")
  }
}

