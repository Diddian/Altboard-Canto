import Foundation

struct TranscriptionBridge: Sendable {

  @discardableResult
  static func writeTranscription(_ text: String) -> Bool {
    let settings = SharedSettings()
    guard let folder = deliveryDirectory, let token = settings.dictationSessionToken else {
      FeatureDiagnostics.record(.bridge, .unavailable)
      return false
    }
    let payload = DictationDelivery(
      schemaVersion: 1, resultID: UUID(), sessionToken: token,
      destinationEpoch: settings.dictationDestinationEpoch, text: text
    )
    do {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      let url = folder.appendingPathComponent(payload.resultID.uuidString + ".json")
      try JSONEncoder().encode(payload).write(
        to: url, options: [.atomic, .completeFileProtectionUnlessOpen]
      )
      FeatureDiagnostics.record(.bridge, .queued, operationID: token, phase: .completed)
      self.postDarwinNotification(DarwinNotificationName.transcriptionReady)
      return true
    } catch {
      FeatureDiagnostics.record(.bridge, .failed, operationID: token, phase: .failed)
      return false
    }
  }

  static func readDelivery(matching token: String? = nil, destinationEpoch: UUID? = nil) -> DictationDelivery? {
    guard let folder = deliveryDirectory else { return nil }
    let files = (try? FileManager.default.contentsOfDirectory(at: folder,
      includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
    let sorted = files.sorted {
      ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
        > ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
    }
    var latest: DictationDelivery?
    for url in sorted.prefix(64) {
      guard let bytes = try? Data(contentsOf: url),
            let result = try? JSONDecoder().decode(DictationDelivery.self, from: bytes),
            result.schemaVersion == 1 else { continue }
      if latest == nil { latest = result }
      if let token, result.sessionToken == token, result.destinationEpoch == destinationEpoch { return result }
    }
    // A scoped request must never fall back to a result from another field/session.
    return token == nil && destinationEpoch == nil ? latest : nil
  }

  static func readTranscription() -> String? { self.readDelivery()?.text }

  static func acknowledgeDelivery(_ resultID: UUID) {
    guard let url = deliveryDirectory?.appendingPathComponent(resultID.uuidString + ".json") else { return }
    try? FileManager.default.removeItem(at: url)
  }

  static func requestCancellation(for token: String?) {
    guard let token, UUID(uuidString: token) != nil,
          let url = cancellationFileURL else { return }
    try? Data(token.utf8).write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
  }

  static func cancellationToken() -> String? {
    guard let url = cancellationFileURL else { return nil }
    return try? String(contentsOf: url, encoding: .utf8)
  }

  static func requestStop(for token: String?) {
    guard let token, UUID(uuidString: token) != nil,
          let url = stopFileURL else { return }
    try? Data(token.utf8).write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
  }

  static func stopToken() -> String? {
    guard let url = stopFileURL else { return nil }
    return try? String(contentsOf: url, encoding: .utf8)
  }

  private static var stopFileURL: URL? {
    AppGroup.containerURL?.appendingPathComponent("dictation-stop-v1.txt")
  }

  private static var deliveryDirectory: URL? {
    AppGroup.containerURL?.appendingPathComponent("transcription-outbox-v1", isDirectory: true)
  }

  private static var cancellationFileURL: URL? {
    AppGroup.containerURL?.appendingPathComponent("dictation-cancel-v1.txt")
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
    if let delivery = self.readDelivery(),
       delivery.sessionToken == SharedSettings().dictationSessionToken {
      self.acknowledgeDelivery(delivery.resultID)
    }
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

