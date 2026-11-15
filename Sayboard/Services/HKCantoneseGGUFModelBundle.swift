import CryptoKit
import Foundation

/// Pinned model family and verified local GGUF pair. The original ONNX
/// Qwen model has a different variant and is never overwritten by this one.
enum HKCantoneseGGUFModelBundle {
  static let repository = "joe2643/Qwen3-ASR-1.7B-Cantonese-HK-GGUF"
  static let modelName = "Qwen3-ASR-1.7B-Cantonese-HK.Q4_K_M.gguf"
  static let audioName = "Qwen3-ASR-1.7B-Cantonese-HK.mmproj-Q8_0.gguf"
  static let receiptName = ".hk-qwen3-verified.json"

  struct Receipt: Codable, Sendable {
    let revision: String
    let modelSHA256: String
    let audioSHA256: String
    let modelBytes: Int64
    let audioBytes: Int64
  }

  static func locate(in folder: URL) -> URL? {
    guard
      let data = try? Data(contentsOf: folder.appendingPathComponent(receiptName)),
      let receipt = try? JSONDecoder().decode(Receipt.self, from: data),
      receipt.revision.count == 40,
      validHash(receipt.modelSHA256), validHash(receipt.audioSHA256),
      receipt.modelBytes > 1_000_000_000, receipt.audioBytes > 300_000_000,
      fileSize(folder.appendingPathComponent(modelName)) == receipt.modelBytes,
      fileSize(folder.appendingPathComponent(audioName)) == receipt.audioBytes
    else { return nil }
    return folder
  }

  static func validHash(_ hash: String) -> Bool {
    hash.count == 64 && hash.allSatisfy { $0.isHexDigit }
  }

  static func fileSize(_ file: URL) -> Int64? {
    ((try? FileManager.default.attributesOfItem(atPath: file.path))?[.size] as? NSNumber)?.int64Value
  }

  /// Stream from disk. A downloaded speech model must never be hashed in RAM.
  static func sha256(of file: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: file)
    defer { try? handle.close() }
    var digest = SHA256()
    while let bytes = try handle.read(upToCount: 1_048_576), !bytes.isEmpty {
      try Task<Never, Never>.checkCancellation()
      digest.update(data: bytes)
    }
    return digest.finalize().map { String(format: "%02x", $0) }.joined()
  }
}

/// HTTPS + Hugging Face revision pin + LFS SHA-256 checks before atomic install.
@MainActor
enum HKCantoneseGGUFDownloader {
  enum Failure: LocalizedError {
    case catalog, changed, storage, response, checksum, install

    var errorDescription: String? {
      switch self {
      case .catalog: "Could not verify the Hong Kong Qwen3 model repository."
      case .changed: "The Hong Kong Qwen3 model revision changed during download. Retry."
      case .storage: "Not enough free storage for the Hong Kong Qwen3 speech model."
      case .response: "The Hong Kong Qwen3 download failed."
      case .checksum: "Downloaded Hong Kong Qwen3 weights failed SHA-256 verification."
      case .install: "Could not install the verified Hong Kong Qwen3 speech model."
      }
    }
  }

  private struct Revision: Decodable { let sha: String }
  private struct Entry: Decodable {
    let path: String
    let size: Int64?
    let lfs: LFS?
    struct LFS: Decodable { let oid: String?; let size: Int64? }
  }

  static func download(progress: @escaping @MainActor @Sendable (Double) -> Void) async throws {
    let destination = ModelStorageManager.directory(for: .qwen3ASR17BCantoneseHK)
    guard HKCantoneseGGUFModelBundle.locate(in: destination) == nil else {
      progress(1)
      return
    }
    progress(0.01) // Metadata lookup has not transferred model bytes yet.
    let repo = HKCantoneseGGUFModelBundle.repository
    let revision = try await ASRDownloadSources.metadata(
      Revision.self, relativePath: "api/models/\(repo)",
      report: self.recordSourceEvent
    ).sha
    guard revision.count == 40, revision.allSatisfy({ $0.isHexDigit })
    else { throw Failure.catalog }
    let entries = try await ASRDownloadSources.metadata(
      [Entry].self, relativePath: "api/models/\(repo)/tree/\(revision)",
      report: self.recordSourceEvent
    )
    let model = try self.require(entries, name: HKCantoneseGGUFModelBundle.modelName,
                                 minimumSize: 1_000_000_000)
    let audio = try self.require(entries, name: HKCantoneseGGUFModelBundle.audioName,
                                 minimumSize: 300_000_000)
    let required = model.bytes + audio.bytes
    // URLSession's temporary files and the staged installation can overlap.
    if let free = ModelDiskReserve.availableBytes(), free < required * 2 + 600_000_000 {
      throw Failure.storage
    }
    try ModelStorageManager.ensureRootExists()
    let fm = FileManager.default
    let staging = ModelStorageManager.modelsRoot.appendingPathComponent(
      ".hk-asr-" + UUID().uuidString, isDirectory: true
    )
    try fm.createDirectory(at: staging, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: staging) }

    let modelURL = try await self.fetch(
      name: HKCantoneseGGUFModelBundle.modelName, revision: revision,
      expected: model, into: staging
    ) { fraction in
      progress(0.94 * Double(model.bytes) / Double(required) * fraction)
    }
    try Task.checkCancellation()
    let audioURL = try await self.fetch(
      name: HKCantoneseGGUFModelBundle.audioName, revision: revision,
      expected: audio, into: staging
    ) { fraction in
      progress(0.94 * (Double(model.bytes) + Double(audio.bytes) * fraction) / Double(required))
    }
    try Task.checkCancellation()

    guard HKCantoneseGGUFModelBundle.fileSize(modelURL) == model.bytes,
          HKCantoneseGGUFModelBundle.fileSize(audioURL) == audio.bytes else {
      throw Failure.checksum
    }
    let receipt = HKCantoneseGGUFModelBundle.Receipt(
      revision: revision, modelSHA256: model.sha, audioSHA256: audio.sha,
      modelBytes: model.bytes, audioBytes: audio.bytes
    )
    try JSONEncoder().encode(receipt).write(
      to: staging.appendingPathComponent(HKCantoneseGGUFModelBundle.receiptName),
      options: .atomic
    )
    guard HKCantoneseGGUFModelBundle.locate(in: staging) != nil else {
      throw Failure.install
    }

    let backup = ModelStorageManager.modelsRoot.appendingPathComponent(
      ".hk-asr-backup-" + UUID().uuidString, isDirectory: true
    )
    let previousExists = fm.fileExists(atPath: destination.path)
    if previousExists { try fm.moveItem(at: destination, to: backup) }
    do {
      try Task.checkCancellation()
      try fm.moveItem(at: staging, to: destination)
      try? fm.removeItem(at: backup)
    } catch {
      if previousExists { try? fm.moveItem(at: backup, to: destination) }
      throw error
    }
    progress(1)
  }

  private struct Expected: Sendable {
    let bytes: Int64
    let sha: String
  }

  private static func require(_ entries: [Entry], name: String, minimumSize: Int64) throws -> Expected {
    guard let entry = entries.first(where: { $0.path == name }),
          let oid = entry.lfs?.oid, HKCantoneseGGUFModelBundle.validHash(oid),
          let bytes = entry.lfs?.size ?? entry.size, bytes > minimumSize
    else { throw Failure.catalog }
    return Expected(bytes: bytes, sha: oid.lowercased())
  }

  private static func fetch(
    name: String, revision: String, expected: Expected, into folder: URL,
    progress: @escaping @MainActor @Sendable (Double) -> Void
  ) async throws -> URL {
    let temporary = try await ASRDownloadSources.download(
      relativePath: "\(HKCantoneseGGUFModelBundle.repository)/resolve/\(revision)/\(name)?download=true",
      report: self.recordSourceEvent,
      progress: progress,
      verify: { file in
        let digest = try await Task.detached(priority: .utility) {
          try HKCantoneseGGUFModelBundle.sha256(of: file)
        }.value
        try Task.checkCancellation()
        guard digest == expected.sha,
              HKCantoneseGGUFModelBundle.fileSize(file) == expected.bytes
        else { throw Failure.checksum }
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

