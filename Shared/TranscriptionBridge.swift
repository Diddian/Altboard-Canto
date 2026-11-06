import Foundation

struct TranscriptionBridge: Sendable {

  static func writeTranscription(_ text: String) {
    guard let url = transcriptionFileURL else {
      return
    }
    do {
      try Data(text.utf8).write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
      DiagnosticLog.write("bridge: wrote \(text.count) chars")
    } catch {
      DiagnosticLog.write("bridge: WRITE FAILED: \(error.localizedDescription)")
    }
    self.postDarwinNotification(DarwinNotificationName.transcriptionReady)
  }

  static func readTranscription() -> String? {
    guard let url = transcriptionFileURL else {
      return nil
    }
    do {
      let text = try String(contentsOf: url, encoding: .utf8)
      DiagnosticLog.write("bridge: read \(text.count) chars")
      return text
    } catch {
      DiagnosticLog.write("bridge: READ FAILED: \(error.localizedDescription)")
      return nil
    }
  }

  /// Publish a short-lived, local-only processing status for the keyboard.
  /// No artificial percentage: the ONNX offline recognizer exposes no
  /// measurable load/decode progress. The UI displays the real elapsed time.
  static func writeVoiceProgress(_ stage: VoiceProcessingStage, rawPreview: String? = nil) {
    guard let url = voiceProgressFileURL else { return }
    let token = SharedSettings().dictationSessionToken
    let previous = self.readVoiceProgress()
    let sameSession = previous?.sessionToken == token
    let now = Date().timeIntervalSinceReferenceDate
    let progress = VoiceProcessingProgress(
      sessionToken: token,
      stage: stage,
      startedAt: sameSession ? previous!.startedAt : now,
      updatedAt: now,
      rawPreview: rawPreview.map { String($0.prefix(240)) }
        ?? (sameSession ? previous?.rawPreview : nil)
    )
    do {
      let payload = try JSONEncoder().encode(progress)
      try payload.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
      self.postDarwinNotification(DarwinNotificationName.voiceProgressUpdated)
    } catch {
      DiagnosticLog.write("voice progress: write failed: \(error.localizedDescription)")
    }
  }

  static func readVoiceProgress() -> VoiceProcessingProgress? {
    guard let url = voiceProgressFileURL,
          let data = try? Data(contentsOf: url),
          !data.isEmpty
    else { return nil }
    return try? JSONDecoder().decode(VoiceProcessingProgress.self, from: data)
  }

  static func clearVoiceProgress() {
    guard let url = voiceProgressFileURL else { return }
    try? Data().write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
    self.postDarwinNotification(DarwinNotificationName.voiceProgressUpdated)
  }

  static func clearTranscription() {
    guard let url = transcriptionFileURL else { return }
    try? Data().write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
  }

  static func postDarwinNotification(_ name: String) {
    let center = CFNotificationCenterGetDarwinNotifyCenter()
    CFNotificationCenterPostNotification(center, CFNotificationName(name as CFString), nil, nil, true)
  }

  static func observeDarwinNotification(_ name: String, callback: @escaping () -> Void) -> DarwinNotificationObserver {
    DarwinNotificationObserver(name: name, callback: callback)
  }

  private static let transcriptionFileName = "transcription.txt"
  private static let voiceProgressFileName = "voice-progress.json"

  private static var voiceProgressFileURL: URL? {
    AppGroup.containerURL?.appendingPathComponent(voiceProgressFileName)
  }

  private static var transcriptionFileURL: URL? {
    AppGroup.containerURL?.appendingPathComponent(transcriptionFileName)
  }
}

enum VoiceProcessingStage: String, Codable, Sendable {
  case stoppingAudio
  case loadingRecognizer
  case transcribing
  case translating
  case editing
  case finalizing

  var title: String {
    switch self {
    case .stoppingAudio: "Preparing recorded audio"
    case .loadingRecognizer: "Loading offline speech model"
    case .transcribing: "Transcribing speech"
    case .translating: "Translating recognized text"
    case .editing: "Cleaning up recognized text"
    case .finalizing: "Finalizing text"
    }
  }
}

struct VoiceProcessingProgress: Codable, Equatable, Sendable {
  let sessionToken: String?
  let stage: VoiceProcessingStage
  let startedAt: TimeInterval
  let updatedAt: TimeInterval
  let rawPreview: String?
}

final class DarwinNotificationObserver: @unchecked Sendable {

  init(name: String, callback: @escaping () -> Void) {
    self.name = name
    self.callback = callback

    let center = CFNotificationCenterGetDarwinNotifyCenter()
    let observer = Unmanaged.passRetained(self).toOpaque()

    CFNotificationCenterAddObserver(
      center,
      observer,
      { _, observer, _, _, _ in
        guard let observer else { return }
        let obj = Unmanaged<DarwinNotificationObserver>.fromOpaque(observer).takeUnretainedValue()
        obj.callback()
      },
      name as CFString,
      nil,
      .deliverImmediately,
    )
    self.isObserving = true
  }

  deinit {
    if self.isObserving {
      let center = CFNotificationCenterGetDarwinNotifyCenter()
      let observer = Unmanaged.passUnretained(self).toOpaque()
      CFNotificationCenterRemoveObserver(center, observer, CFNotificationName(self.name as CFString), nil)
    }
  }

  func stopObserving() {
    guard self.isObserving else { return }
    self.isObserving = false

    let center = CFNotificationCenterGetDarwinNotifyCenter()
    let observer = Unmanaged.passUnretained(self).toOpaque()
    CFNotificationCenterRemoveObserver(center, observer, CFNotificationName(self.name as CFString), nil)

    Unmanaged.passUnretained(self).release()
  }

  private let name: String
  private let callback: () -> Void
  private var isObserving = false
}
