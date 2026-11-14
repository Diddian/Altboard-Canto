import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

// Standalone App Group bridge verifier: no model, audio or host text involved.
enum LLMAction: String, Codable, Sendable {
  case rewrite, translate
}

enum FeatureDiagnostics {
  enum Area { case bridge }
  enum Event { case unavailable, queued, failed }
  static func record(_ area: Area, _ event: Event) {}
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
  static func main() throws {
    if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--hold-lock" {
      try holdLock(at: CommandLine.arguments[2])
      return
    }
    guard let folder = AppGroup.containerURL else { fatalError("Missing test storage") }
    defer { try? FileManager.default.removeItem(at: folder) }

    let request = LLMRequest(
      text: "sample text", action: .rewrite, customPromptId: nil, language: "en"
    )
    let translation = LLMRequest(
      text: "Hello", action: .translate, customPromptId: nil, language: "en",
      translationTarget: "german", customTranslationLanguage: ""
    )
    // Preserve v1 decoding of pre-translation requests.
    let oldJSON = """
      {"requestID":"00000000-0000-0000-0000-000000000001","text":"old request","action":"rewrite","language":"en"}
      """
    let legacy = try JSONDecoder().decode(LLMRequest.self,
      from: Data(oldJSON.utf8))
    precondition(legacy.translationTarget == nil)
    precondition(legacy.sourceDeliveryID == nil)

    precondition(LLMBridge.writeRequest(translation))
    precondition(LLMBridge.readRequest()?.translationTarget == "german")
    LLMBridge.clearRequest()
    precondition(LLMBridge.readRequest()?.requestID == translation.requestID)
    precondition(!LLMBridge.writeRequest(request))
    precondition(!LLMBridge.writeResult("too early", requestID: translation.requestID))
    precondition(!LLMBridge.writeResult("foreign", requestID: UUID()))

    precondition(LLMBridge.writeStatus(.accepted, requestID: translation.requestID))
    precondition(!LLMBridge.writeStatus(.busy, requestID: translation.requestID))
    precondition(LLMBridge.writeResult("Hallo", requestID: translation.requestID))
    precondition(LLMBridge.readResult(matching: translation.requestID) == "Hallo")
    precondition(LLMBridge.readResult(matching: request.requestID) == nil)
    precondition(!LLMBridge.writeResult("duplicate", requestID: translation.requestID))
    precondition(!LLMBridge.writeRequest(request))
    LLMBridge.clearResult(matching: request.requestID)
    precondition(LLMBridge.readResult(matching: translation.requestID) == "Hallo")
    LLMBridge.clearResult(matching: translation.requestID)
    LLMBridge.clearRequest(matching: translation.requestID)
    precondition(LLMBridge.readRequest() == nil)
    precondition(LLMBridge.readStatus(matching: translation.requestID)?.phase == .completed)
    precondition(!LLMBridge.writeStatus(.failed, requestID: translation.requestID))

    // A recorded ASR source remains owned while the AI request is in flight.
    // A complete result then retains that owner even after the host removes
    // the original request, until the user explicitly recovers the result.
    let deliveryID = UUID()
    let linked = LLMRequest(
      text: "test dictated source", action: .rewrite,
      customPromptId: nil, language: "en", sourceDeliveryID: deliveryID
    )
    precondition(LLMBridge.writeRequest(linked))
    precondition(LLMBridge.readRequest()?.sourceDeliveryID == deliveryID)
    precondition(LLMBridge.ownsDelivery(deliveryID))
    precondition(LLMBridge.writeStatus(.accepted, requestID: linked.requestID))
    precondition(LLMBridge.writeResult("processed source", requestID: linked.requestID))
    precondition(LLMBridge.readResultPayload(matching: linked.requestID)?.sourceDeliveryID == deliveryID)
    precondition(LLMBridge.ownsDelivery(deliveryID))
    // Simulate keyboard/controller destruction after host completion.
    LLMBridge.clearRequest(matching: linked.requestID)
    precondition(LLMBridge.readRequest() == nil)
    precondition(LLMBridge.recoverableResult()?.requestID == linked.requestID)
    precondition(LLMBridge.recoverableResult()?.text == "processed source")
    precondition(!LLMBridge.writeRequest(request))
    precondition(!LLMBridge.ownsDelivery(UUID()))
    LLMBridge.clearResult(matching: linked.requestID)
    precondition(LLMBridge.recoverableResult() == nil)
    precondition(!LLMBridge.ownsDelivery(deliveryID))
    precondition(LLMBridge.writeRequest(request))
    precondition(LLMBridge.writeStatus(.cancelled, requestID: request.requestID))
    precondition(!LLMBridge.writeResult("late", requestID: request.requestID))
    LLMBridge.clearRequest(matching: request.requestID)
    precondition(LLMBridge.readRequest() == nil)

    // Bad pending JSON is still owned state, never overwrite it.
    let requestURL = folder.appendingPathComponent("llm_request.json")
    let malformed = Data("invalid-while-pending".utf8)
    try malformed.write(to: requestURL, options: .atomic)
    precondition(!LLMBridge.writeRequest(request))
    let preserved = try Data(contentsOf: requestURL)
    precondition(preserved == malformed)
    try FileManager.default.removeItem(at: requestURL)

    // The nested request->status write must not deadlock on the same lock.
    // Cancelled UUIDs remain terminal; a fresh operation needs a new UUID.
    let lockRequest = LLMRequest(
      text: "new attempt", action: .rewrite, customPromptId: nil, language: "en"
    )
    precondition(LLMBridge.writeRequest(lockRequest))
    precondition(LLMBridge.readStatus(matching: lockRequest.requestID)?.phase == .requested)

    // An independent process holds the App Group lock; keyboard APIs must
    // return in bounded time without touching its outstanding request.
    let ready = folder.appendingPathComponent("holder.ready")
    let holder = Process()
    holder.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
    holder.arguments = ["--hold-lock", folder.path]
    // Child process shares the exact same test folder via argv.
    try holder.run()
    var signaled = false
    for _ in 0..<200 {
      if FileManager.default.fileExists(atPath: ready.path) {
        signaled = true
        break
      }
      usleep(5_000)
    }
    precondition(signaled, "Child never acquired the bridge lock")
    let started = Date()
    precondition(!LLMBridge.writeStatus(.accepted, requestID: lockRequest.requestID))
    let waited = Date().timeIntervalSince(started)
    precondition(waited < 0.15, "Keyboard bridge waited too long for a busy lock")
    print("bridge_lock_contended_wait_ms=\(Int(waited * 1_000))")
    precondition(LLMBridge.readRequest()?.requestID == lockRequest.requestID)
    holder.waitUntilExit()
    precondition(holder.terminationStatus == 0)
    precondition(LLMBridge.writeStatus(.accepted, requestID: lockRequest.requestID))
    precondition(LLMBridge.writeResult("rewritten", requestID: lockRequest.requestID))
    precondition(LLMBridge.readResult(matching: lockRequest.requestID) == "rewritten")
    LLMBridge.clearResult(matching: lockRequest.requestID)
    LLMBridge.clearRequest(matching: lockRequest.requestID)
    precondition(LLMBridge.readRequest() == nil)

    print("LLM bridge: lifecycle, second-owner rejection, stale/cancelled results, malformed pending data, reentry and bounded process contention PASS")
  }

  // Standalone verifier is itself the child process holding a local-only lock.
  // Executed before the normal verification path when --hold-lock is present.
  static func holdLock(at folder: String) throws {
    let fd = open(URL(fileURLWithPath: folder)
      .appendingPathComponent("llm-bridge-v1.lock").path,
      O_CREAT | O_RDWR, mode_t(0o600))
    precondition(fd >= 0)
    defer { _ = close(fd) }
    precondition(flock(fd, LOCK_EX) == 0)
    defer { _ = flock(fd, LOCK_UN) }
    try Data().write(to: URL(fileURLWithPath: folder)
      .appendingPathComponent("holder.ready"), options: .atomic)
    usleep(300_000)
  }
}
