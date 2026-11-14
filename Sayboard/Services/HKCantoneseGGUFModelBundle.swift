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
    let repo = HKCantoneseGGUFModelBundle.repository
    let revisionURL = URL(string: "https://huggingface.co/api/models/\(repo)")!
    let (revisionData, revisionResponse) = try await URLSession.shared.data(from: revisionURL)
    guard (revisionResponse as? HTTPURLResponse)?.statusCode == 200,
          let revision = try? JSONDecoder().decode(Revision.self, from: revisionData).sha,
          revision.count == 40, revision.allSatisfy({ $0.isHexDigit })
    else { throw Failure.catalog }
    let listURL = URL(string: "https://huggingface.co/api/models/\(repo)/tree/\(revision)")!
    let (listData, listResponse) = try await URLSession.shared.data(from: listURL)
    guard (listResponse as? HTTPURLResponse)?.statusCode == 200,
          let entries = try? JSONDecoder().decode([Entry].self, from: listData)
    else { throw Failure.catalog }
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

  private struct Expected {
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
    guard let url = URL(string: "https://huggingface.co/\(HKCantoneseGGUFModelBundle.repository)/resolve/\(revision)/\(name)?download=true") else {
      throw Failure.catalog
    }
    let observer = HKGGUFDownloadObserver { fraction in
      Task { @MainActor in progress(fraction) }
    }
    let (temp, response) = try await URLSession.shared.download(from: url, delegate: observer)
    try Task.checkCancellation()
    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
      throw Failure.response
    }
    let digest = try await Task.detached(priority: .utility) {
      try HKCantoneseGGUFModelBundle.sha256(of: temp)
    }.value
    try Task.checkCancellation()
    guard digest == expected.sha, HKCantoneseGGUFModelBundle.fileSize(temp) == expected.bytes else {
      throw Failure.checksum
    }
    let target = folder.appendingPathComponent(name)
    try FileManager.default.moveItem(at: temp, to: target)
    return target
  }
}

private final class HKGGUFDownloadObserver: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
  let report: @Sendable (Double) -> Void
  init(report: @escaping @Sendable (Double) -> Void) { self.report = report }

  func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask,
    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
    totalBytesExpectedToWrite: Int64
  ) {
    guard totalBytesExpectedToWrite > 0 else { return }
    report(min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
  }

  func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {}
}
