import Foundation

/// Explicit, checksum-verified download of the two files actually required by
/// the pinned SenseVoice INT8 model. No separate server or archive extractor.
@MainActor
enum SenseVoiceModelDownloader {
  enum DownloadError: LocalizedError {
    case storage, invalidResponse, checksum, invalidTokenizer, install

    var errorDescription: String? {
      switch self {
      case .storage: "Not enough free storage for SenseVoice Small."
      case .invalidResponse: "The SenseVoice download server returned an invalid response."
      case .checksum: "The SenseVoice model checksum did not match."
      case .invalidTokenizer: "The SenseVoice vocabulary was invalid."
      case .install: "Could not finish installing the SenseVoice model."
      }
    }
  }

  static func download(progress: @escaping @MainActor @Sendable (Double) -> Void) async throws {
    let destination = ModelStorageManager.directory(for: .senseVoiceSmall)
    let fm = FileManager.default
    let required: Int64 = 550_000_000
    if let available = ModelDiskReserve.availableBytes(), available < required {
      throw DownloadError.storage
    }
    progress(0.01) // Connection establishment is not yet transferred bytes.
    try ModelStorageManager.ensureRootExists()
    let staging = ModelStorageManager.modelsRoot
      .appendingPathComponent(".sensevoice-" + UUID().uuidString, isDirectory: true)
    try fm.createDirectory(at: staging, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: staging) }
    do {
      _ = try await self.fetch(
        name: "model.int8.onnx", into: staging,
        progress: { value in progress(value * 0.94) }
      )
      try Task.checkCancellation()
      progress(0.95)
      _ = try await self.fetch(
        name: "tokens.txt", into: staging, progress: { value in progress(0.95 + value * 0.02) }
      )
      try Task.checkCancellation()
      try SenseVoiceModelBundle.modelSHA256.write(
        to: staging.appendingPathComponent(SenseVoiceModelBundle.markerName),
        atomically: true, encoding: .utf8
      )
      guard SenseVoiceModelBundle.isValid(directory: staging) else {
        throw DownloadError.install
      }
      let backup = ModelStorageManager.modelsRoot
        .appendingPathComponent(".sensevoice-backup-" + UUID().uuidString)
      let hadPrevious = fm.fileExists(atPath: destination.path)
      if hadPrevious { try fm.moveItem(at: destination, to: backup) }
      do {
        try Task.checkCancellation()
        try fm.moveItem(at: staging, to: destination)
        try? fm.removeItem(at: backup)
      } catch {
        if hadPrevious { try? fm.moveItem(at: backup, to: destination) }
        throw error
      }
      progress(1)
    } catch {
      FeatureDiagnostics.record(
        .speechModel, Task.isCancelled ? .cancelled : .failed
      )
      throw error
    }
  }

  private static func fetch(
    name: String, into folder: URL,
    progress: @escaping @MainActor @Sendable (Double) -> Void
  ) async throws -> URL {
    let temporary = try await ASRDownloadSources.download(
      relativePath: "\(SenseVoiceModelBundle.repository)/resolve/main/\(name)?download=true",
      report: self.recordSourceEvent,
      progress: progress,
      verify: { file in
        switch name {
        case "model.int8.onnx":
          let digest = try await Task.detached(priority: .utility) {
            try BackgroundDownloadManager.computeSHA256(of: file)
          }.value
          guard digest == SenseVoiceModelBundle.modelSHA256 else {
            throw DownloadError.checksum
          }
        case "tokens.txt":
          let bytes = try Data(contentsOf: file)
          guard (100_000...1_000_000).contains(bytes.count),
                bytes.starts(with: Data("<unk> 0".utf8))
          else { throw DownloadError.invalidTokenizer }
        default:
          throw DownloadError.invalidResponse
        }
      }
    )
    let target = folder.appendingPathComponent(name)
    try FileManager.default.moveItem(at: temporary, to: target)
    return target
  }

  private static func recordSourceEvent(_ event: ASRDownloadSources.Event) {
    switch event {
    case .sourceFallback:
      FeatureDiagnostics.record(.speechModel, .downloadSourceFallback)
    case .firstByte(milliseconds: let ms):
      FeatureDiagnostics.record(.speechModel, .downloadFirstByte, durationMs: ms)
    }
  }

}
