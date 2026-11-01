import Foundation

/// Foreground-only on-device model installer. Files are downloaded to disk, not into memory.
/// The source is a compatible Hugging Face sherpa-onnx Qwen3-ASR repository.
@MainActor
enum QwenHubDownloader {
  struct TreeEntry: Decodable {
    let path: String
    let type: String
    let size: Int64?
    let lfs: LFS?
    struct LFS: Decodable { let oid: String? }
  }

  enum DownloadError: LocalizedError {
    case invalidRepository
    case catalog(String)
    case incompatible(String)
    case insufficientStorage(Int64)
    case sourceChanged
    case file(String)

    var errorDescription: String? {
      switch self {
      case .invalidRepository:
        "Invalid Hugging Face repository address"
      case .catalog(let detail):
        "Cannot read Hugging Face model files: \(detail)"
      case .incompatible(let detail):
        "This repository is not a compatible sherpa-onnx Qwen3 model: \(detail)"
      case .insufficientStorage(let bytes):
        "Not enough iPhone storage; model needs roughly \(bytes / 1_000_000_000) GB free"
      case .sourceChanged:
        "A different source was partially installed. Remove the old Qwen model to switch repositories."
      case .file(let detail):
        "File download failed: \(detail)"
      }
    }
  }

  static func download(
    variant: ModelVariant,
    progress: @escaping @MainActor @Sendable (Double) -> Void
  ) async throws {
    guard variant.engine == .qwen3,
          variant.isSupportedOnCurrentDevice
    else { throw DownloadError.incompatible("This model exceeds the configured RAM threshold") }
    let repo = CustomQwenModelSource.repositoryID(for: variant)
    guard CustomQwenModelSource.normalizedRepositoryID(repo) != nil else {
      throw DownloadError.invalidRepository
    }
    progress(0.01)
    let nodes = try await listFiles(repository: repo)
    let files = try selectedFiles(nodes)
    let total = max(Int64(1), files.reduce(Int64(0)) { $0 + ($1.size ?? 0) })
    let needed = Int64(Double(total) * 1.10) + 100_000_000
    if let free = ModelDiskReserve.availableBytes(), free < needed {
      throw DownloadError.insufficientStorage(needed)
    }

    try ModelStorageManager.ensureRootExists()
    let root = ModelStorageManager.directory(for: variant)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let sourceMarker = root.appendingPathComponent(".source-repository")
    if FileManager.default.fileExists(atPath: sourceMarker.path) {
      let previous = (try? String(contentsOf: sourceMarker, encoding: .utf8)) ?? ""
      guard previous == repo else { throw DownloadError.sourceChanged }
    } else {
      try repo.write(to: sourceMarker, atomically: true, encoding: .utf8)
    }

    let fm = FileManager.default
    var complete: Int64 = 0
    for item in files {
      try Task.checkCancellation()
      guard item.path.components(separatedBy: "/").allSatisfy({ $0 != ".." && !$0.isEmpty }) else {
        throw DownloadError.incompatible("Unsafe file path in model metadata")
      }
      let destination = root.appendingPathComponent(item.path)
      if try isVerifiedExisting(destination, item: item) {
        complete += item.size ?? 0
        progress(min(0.94, Double(complete) / Double(total) * 0.94))
        continue
      }

      try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
      var errors = [String]()
      var received = false
      for host in ["huggingface.co", "hf-mirror.com"] {
        try Task.checkCancellation()
        guard let url = URL(string: "https://\(host)/\(repo)/resolve/main/\(item.path)?download=true") else {
          errors.append("Invalid source URL")
          continue
        }
        let bytesBefore = complete
        let observer = QwenDownloadProgressObserver { fraction in
          Task { @MainActor in
            progress(min(0.94, (Double(bytesBefore) + Double(item.size ?? 0) * fraction) / Double(total) * 0.94))
          }
        }
        do {
          let (temp, response) = try await URLSession.shared.download(from: url, delegate: observer)
          try Task.checkCancellation()
          guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw DownloadError.file("\(host) HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
          }
          try verifyFile(temp, item: item)
          if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
          try fm.moveItem(at: temp, to: destination)
          received = true
          break
        } catch {
          if Task.isCancelled { throw CancellationError() }
          errors.append("\(host): \(error.localizedDescription)")
        }
      }
      guard received else {
        throw DownloadError.file("\(item.path) — \(errors.joined(separator: " | "))")
      }
      complete += item.size ?? 0
      progress(min(0.94, Double(complete) / Double(total) * 0.94))
    }
    guard Qwen3ModelBundle.isValid(directory: root) else {
      throw DownloadError.incompatible("Required ONNX or tokenizer files missing")
    }
    progress(1)
  }

  private static func listFiles(repository repo: String) async throws -> [TreeEntry] {
    var problems = [String]()
    for host in ["huggingface.co", "hf-mirror.com"] {
      let urlString = "https://\(host)/api/models/\(repo)/tree/main?recursive=true"
      guard let url = URL(string: urlString) else { continue }
      do {
        var request = URLRequest(url: url)
        request.timeoutInterval = 45
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
          throw DownloadError.catalog("\(host) HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        return try JSONDecoder().decode([TreeEntry].self, from: data)
      } catch {
        problems.append("\(host): \(error.localizedDescription)")
      }
    }
    throw DownloadError.catalog(problems.joined(separator: " | "))
  }

  private static func selectedFiles(_ nodes: [TreeEntry]) throws -> [TreeEntry] {
    let available = nodes.filter { $0.type == "file" }
    func required(_ path: String) throws -> TreeEntry {
      guard let file = available.first(where: { $0.path == path }) else {
        throw DownloadError.incompatible("Missing \(path)")
      }
      return file
    }
    let frontend = try required("conv_frontend.onnx")
    let encoder = try required(available.contains { $0.path == "encoder.int8.onnx" }
      ? "encoder.int8.onnx" : "encoder.onnx")
    let decoder = try required(available.contains { $0.path == "decoder.int8.onnx" }
      ? "decoder.int8.onnx" : "decoder.onnx")
    var files = [frontend, encoder, decoder]
    for model in [encoder, decoder] {
      if let weights = available.first(where: { $0.path == model.path + ".data" }) {
        files.append(weights)
      }
    }
    for path in ["tokenizer/vocab.json", "tokenizer/merges.txt", "tokenizer/tokenizer_config.json"] {
      files.append(try required(path))
    }
    guard files.allSatisfy({ ($0.size ?? 0) > 0 }) else {
      throw DownloadError.incompatible("Model file sizes are missing")
    }
    return files
  }

  private static func isVerifiedExisting(_ url: URL, item: TreeEntry) throws -> Bool {
    guard FileManager.default.fileExists(atPath: url.path) else { return false }
    do {
      try verifyFile(url, item: item)
      return true
    } catch { return false }
  }

  private static func verifyFile(_ url: URL, item: TreeEntry) throws {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    let size = (attributes[.size] as? NSNumber)?.int64Value ?? -1
    guard size == item.size else { throw DownloadError.file("\(item.path): unexpected byte size") }
    if let expectedHash = item.lfs?.oid, expectedHash.count == 64 {
      let actualHash = try BackgroundDownloadManager.computeSHA256(of: url)
      guard actualHash == expectedHash.lowercased() else {
        throw DownloadError.file("\(item.path): SHA-256 mismatch")
      }
    }
  }
}

private final class QwenDownloadProgressObserver: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
  let report: @Sendable (Double) -> Void
  init(report: @escaping @Sendable (Double) -> Void) { self.report = report }

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
