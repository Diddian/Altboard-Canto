import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Speech transcription only. Never stores the host application's text.
struct ExperimentalLiveTranscript: Codable, Sendable {
  let sessionToken: String
  let revision: Int
  let text: String
  let updatedAt: TimeInterval
}

enum ExperimentalLiveTranscription {
  static let fileName = "experimental-live-transcript.json"
  private static let hostReceiptPrefix = "experimental-live-inserted-"

  /// A text-free, request-scoped receipt is committed BEFORE any UIKit write.
  /// A fresh keyboard controller must not replay a partially inserted session.
  static func hasHostInsertionStarted(
    for token: String, container: URL? = AppGroup.containerURL
  ) -> Bool {
    guard let url = self.hostReceiptURL(for: token, container: container) else { return true }
    return FileManager.default.fileExists(atPath: url.path)
  }

  /// O_EXCL is atomic across keyboard processes. A failed receipt write
  /// disables live insertion; the final transcript remains in History/outbox.
  @discardableResult
  static func claimHostInsertion(
    for token: String, container: URL? = AppGroup.containerURL
  ) -> Bool {
    guard let url = self.hostReceiptURL(for: token, container: container) else { return false }
    return url.path.withCString { path in
      let fd = open(path, O_WRONLY | O_CREAT | O_EXCL, mode_t(0o600))
      guard fd >= 0 else { return false }
      _ = close(fd)
      return true
    }
  }

  private static func hostReceiptURL(for token: String, container: URL?) -> URL? {
    guard UUID(uuidString: token) != nil, let container else { return nil }
    return container.appendingPathComponent(hostReceiptPrefix + token + ".receipt")
  }

  static func read() -> ExperimentalLiveTranscript? {
    guard let url = AppGroup.containerURL?.appendingPathComponent(fileName),
          let data = try? Data(contentsOf: url),
          data.count <= 128 * 1_024 else { return nil }
    return try? JSONDecoder().decode(ExperimentalLiveTranscript.self, from: data)
  }

  @discardableResult
  static func write(sessionToken: String, revision: Int, text: String) -> Bool {
    guard let url = AppGroup.containerURL?.appendingPathComponent(fileName),
          !sessionToken.isEmpty, revision > 0, !text.isEmpty else { return false }
    let update = ExperimentalLiveTranscript(sessionToken: sessionToken,
      revision: revision, text: String(text.prefix(3000)),
      updatedAt: Date().timeIntervalSinceReferenceDate)
    guard let payload = try? JSONEncoder().encode(update),
          payload.count <= 128 * 1_024 else { return false }
    do {
      try payload.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
      TranscriptionBridge.postDarwinNotification(DarwinNotificationName.experimentalLiveTranscriptUpdated)
      return true
    } catch {
      DiagnosticLog.write("live dictation: update file write failed")
      return false
    }
  }

  static func clear() {
    guard let container = AppGroup.containerURL else { return }
    try? FileManager.default.removeItem(at: container.appendingPathComponent(fileName))
    // A new capture invalidates receipts for older tokens. Retain the current
    // receipt until the final delivery is consumed or a newer capture starts.
    let keep = SharedSettings().dictationSessionToken
    let keepName = keep.map { hostReceiptPrefix + $0 + ".receipt" }
    if let files = try? FileManager.default.contentsOfDirectory(
      at: container, includingPropertiesForKeys: nil
    ) {
      for file in files where file.lastPathComponent.hasPrefix(hostReceiptPrefix)
        && file.lastPathComponent.hasSuffix(".receipt")
        && file.lastPathComponent != keepName {
        try? FileManager.default.removeItem(at: file)
      }
    }
  }
}

/// Non-destructive spacing between recognized speech segments.
enum ExperimentalSpeechSegments {
  static func append(_ segment: String, to previous: String) -> String {
    let next = segment.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !next.isEmpty else { return previous }
    guard let last = previous.last, let first = next.first else { return next }
    let chinese = CharacterSet(charactersIn: "，。！？；：、」』）】》")
    let nextIsPunctuation = first.unicodeScalars.allSatisfy { chinese.contains($0) }
    let noSpace = last.isWhitespace || nextIsPunctuation
      || (last.unicodeScalars.first.map { $0.value >= 0x3400 && $0.value <= 0x9FFF } ?? false)
      || (first.unicodeScalars.first.map { $0.value >= 0x3400 && $0.value <= 0x9FFF } ?? false)
    return previous + (noSpace ? "" : " ") + next
  }
}

/// Cross-process first-text timing only. Never persist recognized or host text.
/// At most one timestamp per milestone for the latest dictation request.
enum LiveDictationLatency {
  enum Point: String, CaseIterable {
    case audioCaptured, modelReady, firstChunkReady, firstDecoded, firstPublished, firstHostInsert
  }

  private static let prefix = "canto.liveLatency.v1."

  static func begin(token: String, at time: TimeInterval = Date().timeIntervalSinceReferenceDate) {
    guard UUID(uuidString: token) != nil, let defaults = AppGroup.sharedDefaults else { return }
    for point in Point.allCases { defaults.removeObject(forKey: prefix + point.rawValue) }
    defaults.set(time, forKey: prefix + "startedAt")
    defaults.set(token, forKey: prefix + "sessionToken")
    defaults.synchronize()
  }

  static func mark(_ point: Point, token: String,
                   at time: TimeInterval = Date().timeIntervalSinceReferenceDate) {
    guard let defaults = AppGroup.sharedDefaults else { return }
    defaults.synchronize()
    guard defaults.string(forKey: prefix + "sessionToken") == token,
          defaults.object(forKey: prefix + point.rawValue) == nil else { return }
    defaults.set(time, forKey: prefix + point.rawValue)
  }

  static func elapsedMs(_ point: Point) -> Int? {
    guard let defaults = AppGroup.sharedDefaults else { return nil }
    defaults.synchronize()
    let started = defaults.double(forKey: prefix + "startedAt")
    let end = defaults.double(forKey: prefix + point.rawValue)
    guard started > 0, end >= started, end - started < 3600 else { return nil }
    return Int((end - started) * 1_000)
  }

  static func label(_ point: Point) -> String {
    guard let elapsed = elapsedMs(point) else { return "Not measured" }
    return String(format: "%.2f s", Double(elapsed) / 1_000)
  }

  static func exportDurationsMs() -> [String: Int] {
    Dictionary(uniqueKeysWithValues: Point.allCases.compactMap { point in
      elapsedMs(point).map { (point.rawValue, $0) }
    })
  }

  static func clear() {
    guard let defaults = AppGroup.sharedDefaults else { return }
    for point in Point.allCases { defaults.removeObject(forKey: prefix + point.rawValue) }
    defaults.removeObject(forKey: prefix + "startedAt")
    defaults.removeObject(forKey: prefix + "sessionToken")
  }
}
