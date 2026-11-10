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
    try ModelStorageManager.ensureRootExists()
    let staging = ModelStorageManager.modelsRoot
      .appendingPathComponent(".sensevoice-" + UUID().uuidString, isDirectory: true)
    try fm.createDirectory(at: staging, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: staging) }
    do {
      let model = try await self.fetch(
        name: "model.int8.onnx", into: staging,
        progress: { value in progress(value * 0.94) }
      )
      try Task.checkCancellation()
      guard try BackgroundDownloadManager.computeSHA256(of: model)
              == SenseVoiceModelBundle.modelSHA256 else {
        throw DownloadError.checksum
      }
      progress(0.95)
      let tokens = try await self.fetch(
        name: "tokens.txt", into: staging, progress: { value in progress(0.95 + value * 0.02) }
      )
      let data = try Data(contentsOf: tokens)
      guard (100_000...1_000_000).contains(data.count),
            String(data: data.prefix(100), encoding: .utf8)?.contains("<unk> 0") == true
      else { throw DownloadError.invalidTokenizer }
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
    let source =
      "https://huggingface.co/" + SenseVoiceModelBundle.repository +
      "/resolve/main/" + name + "?download=true"
    guard let url = URL(string: source) else { throw DownloadError.invalidResponse }
    let observer = SenseVoiceDownloadProgressObserver { fraction in
      Task { @MainActor in progress(fraction) }
    }
    let (temp, response) = try await URLSession.shared.download(from: url, delegate: observer)
    try Task.checkCancellation()
    guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
      throw DownloadError.invalidResponse
    }
    let target = folder.appendingPathComponent(name)
    try FileManager.default.moveItem(at: temp, to: target)
    return target
  }
}


private final class SenseVoiceDownloadProgressObserver: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
  let report: @Sendable (Double) -> Void

  init(report: @escaping @Sendable (Double) -> Void) {
    self.report = report
  }

  func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask,
    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
    totalBytesExpectedToWrite: Int64
  ) {
    guard totalBytesExpectedToWrite > 0 else { return }
    self.report(min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
  }

  func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {}
}
