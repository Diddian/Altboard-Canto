import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A bounded, verified download path shared by the two optional Cantonese ASR models.
/// Only the caller can accept a downloaded file; this helper never trusts a mirror alone.
@MainActor
enum ASRDownloadSources {
  enum Event: Sendable {
    case firstByte(milliseconds: Int)
    case sourceFallback
  }

  enum SourceError: LocalizedError {
    case status(host: String, code: Int)
    case allFailed([String])

    var errorDescription: String? {
      switch self {
      case .status(let host, let code):
        "\(host) returned HTTP \(code)"
      case .allFailed(let errors):
        "Model sources unavailable: \(errors.joined(separator: " | "))"
      }
    }
  }

  static let hosts = ["huggingface.co", "hf-mirror.com"]
  static let metadataTimeout: TimeInterval = 12
  static let transferIdleTimeout: TimeInterval = 25

  private static let defaultSession: URLSession = {
    let config = URLSessionConfiguration.ephemeral
    #if !canImport(FoundationNetworking)
    config.waitsForConnectivity = false
    #endif
    config.timeoutIntervalForRequest = transferIdleTimeout
    // Large model transfers must not time out merely because they take a while.
    config.timeoutIntervalForResource = 7_200
    return URLSession(configuration: config)
  }()

  /// A single retry owner for metadata and binary transfers.
  /// Cancellation never triggers a request to the next host.
  static func withFallback<T>(
    report: @escaping @MainActor @Sendable (Event) -> Void = { _ in },
    attempt: (String) async throws -> T
  ) async throws -> T {
    var errors: [String] = []
    for (index, host) in hosts.enumerated() {
      try Task.checkCancellation()
      do {
        return try await attempt(host)
      } catch {
        if Task.isCancelled || error is CancellationError { throw CancellationError() }
        errors.append("\(host): \(error.localizedDescription)")
        if index + 1 < hosts.count { report(.sourceFallback) }
      }
    }
    throw SourceError.allFailed(errors)
  }

  /// Decode on each host before declaring success. Invalid JSON also retries.
  static func metadata<T: Decodable>(
    _ type: T.Type,
    relativePath: String,
    session: URLSession? = nil,
    report: @escaping @MainActor @Sendable (Event) -> Void = { _ in }
  ) async throws -> T {
    let client = session ?? defaultSession
    return try await withFallback(report: report) { host in
      var request = URLRequest(url: try self.url(host: host, relativePath: relativePath))
      request.timeoutInterval = metadataTimeout
      request.cachePolicy = .reloadIgnoringLocalCacheData
      let (body, response) = try await client.data(for: request)
      guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
        throw SourceError.status(host: host, code: (response as? HTTPURLResponse)?.statusCode ?? -1)
      }
      return try JSONDecoder().decode(T.self, from: body)
    }
  }

  /// Validation runs BEFORE acceptance. A corrupted file retries the mirror.
  static func download(
    relativePath: String,
    session: URLSession? = nil,
    report: @escaping @MainActor @Sendable (Event) -> Void = { _ in },
    progress: @escaping @MainActor @Sendable (Double) -> Void,
    verify: @escaping @Sendable (URL) async throws -> Void
  ) async throws -> URL {
    let client = session ?? defaultSession
    return try await withFallback(report: report) { host in
      var request = URLRequest(url: try self.url(host: host, relativePath: relativePath))
      request.timeoutInterval = transferIdleTimeout
      request.cachePolicy = .reloadIgnoringLocalCacheData
      let observer = ASRDownloadProgressObserver(
        reportProgress: progress,
        reportFirstByte: { ms in report(.firstByte(milliseconds: ms)) }
      )
      let (temporary, response) = try await client.download(for: request, delegate: observer)
      try Task.checkCancellation()
      guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
        throw SourceError.status(host: host, code: (response as? HTTPURLResponse)?.statusCode ?? -1)
      }
      try await verify(temporary)
      try Task.checkCancellation()
      return temporary
    }
  }

  private static func url(host: String, relativePath: String) throws -> URL {
    guard !relativePath.isEmpty, !relativePath.hasPrefix("/"),
          !relativePath.contains(".."), !relativePath.contains("://"),
          let url = URL(string: "https://\(host)/\(relativePath)")
    else { throw URLError(.badURL) }
    return url
  }
}

private final class ASRDownloadProgressObserver: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
  private let reportProgress: @MainActor @Sendable (Double) -> Void
  private let reportFirstByte: @MainActor @Sendable (Int) -> Void
  private let began = Date()
  private let lock = NSLock()
  private var reportedFirstByte = false

  init(
    reportProgress: @escaping @MainActor @Sendable (Double) -> Void,
    reportFirstByte: @escaping @MainActor @Sendable (Int) -> Void
  ) {
    self.reportProgress = reportProgress
    self.reportFirstByte = reportFirstByte
  }

  func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask,
    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
    totalBytesExpectedToWrite: Int64
  ) {
    lock.lock()
    let first = !reportedFirstByte && totalBytesWritten > 0
    if first { reportedFirstByte = true }
    lock.unlock()
    let elapsedMs = Int(Date().timeIntervalSince(began) * 1_000)
    let fraction = totalBytesExpectedToWrite > 0
      ? min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)) : 0
    Task { @MainActor in
      if first { reportFirstByte(elapsedMs) }
      reportProgress(fraction)
    }
  }

  func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {}
}
