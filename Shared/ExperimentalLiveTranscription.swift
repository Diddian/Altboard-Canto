import Foundation

/// Speech transcription only. Never stores the host application's text.
struct ExperimentalLiveTranscript: Codable, Sendable {
  let sessionToken: String
  let revision: Int
  let text: String
  let updatedAt: TimeInterval
}

enum ExperimentalLiveTranscription {
  static let fileName = "experimental-live-transcript.json"

  static func read() -> ExperimentalLiveTranscript? {
    guard let url = AppGroup.containerURL?.appendingPathComponent(fileName),
          let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder().decode(ExperimentalLiveTranscript.self, from: data)
  }

  static func write(sessionToken: String, revision: Int, text: String) {
    guard let url = AppGroup.containerURL?.appendingPathComponent(fileName),
          !sessionToken.isEmpty, revision > 0, !text.isEmpty else { return }
    let update = ExperimentalLiveTranscript(sessionToken: sessionToken,
      revision: revision, text: String(text.prefix(3000)),
      updatedAt: Date().timeIntervalSinceReferenceDate)
    guard let payload = try? JSONEncoder().encode(update) else { return }
    do {
      try payload.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
      TranscriptionBridge.postDarwinNotification(DarwinNotificationName.experimentalLiveTranscriptUpdated)
    } catch {
      DiagnosticLog.write("live dictation: update file write failed")
    }
  }

  static func clear() {
    guard let url = AppGroup.containerURL?.appendingPathComponent(fileName) else { return }
    try? FileManager.default.removeItem(at: url)
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
