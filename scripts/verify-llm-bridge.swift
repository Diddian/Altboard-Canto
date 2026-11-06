import Foundation

enum LLMAction: String, Codable, Sendable { case rewrite }
enum AppGroup {
  static let containerURL: URL? = {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      "altboard-baseline-bridge-" + UUID().uuidString)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }()
}
@main
enum VerifyLLMBridge {
  static func main() throws {
    guard let root = AppGroup.containerURL else { fatalError("Missing test directory") }
    defer { try? FileManager.default.removeItem(at: root) }
    LLMBridge.clearRequest()
    LLMBridge.clearResult()
    precondition(LLMBridge.readRequest() == nil)
    precondition(LLMBridge.readResult() == nil)
    let request = LLMRequest(text: "fixture only", action: .rewrite,
                             customPromptId: nil, language: "yue")
    LLMBridge.writeRequest(request)
    precondition(LLMBridge.readRequest()?.text == request.text)
    precondition(LLMBridge.readRequest()?.language == "yue")
    LLMBridge.writeResult("result fixture")
    precondition(LLMBridge.readResult() == "result fixture")
    LLMBridge.clearResult()
    LLMBridge.clearRequest()
    precondition(LLMBridge.readResult() == nil)
    precondition(LLMBridge.readRequest() == nil)
    print("Baseline LLM bridge request/result round-trip passed")
  }
}
