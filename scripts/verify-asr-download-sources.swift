import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private struct Revision: Decodable { let sha: String }

private final class MockURLProtocol: URLProtocol {
  nonisolated(unsafe) static var response: @Sendable (URLRequest) -> (Int, Data) = { _ in
    (500, Data())
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func stopLoading() {}
  override func startLoading() {
    guard let url = request.url else { return }
    let (status, data) = Self.response(request)
    let reply = HTTPURLResponse(
      url: url, statusCode: status, httpVersion: "HTTP/1.1",
      headerFields: ["Content-Length": String(data.count)]
    )!
    client?.urlProtocol(self, didReceive: reply, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: data)
    client?.urlProtocolDidFinishLoading(self)
  }
}

@main
struct VerifyASRDownloadSources {
  @MainActor static func main() async throws {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    let mockSession = URLSession(configuration: config)
    defer { mockSession.invalidateAndCancel() }

    precondition(ASRDownloadSources.hosts == ["huggingface.co", "hf-mirror.com"])
    precondition(ASRDownloadSources.metadataTimeout <= 15)
    precondition(ASRDownloadSources.transferIdleTimeout <= 30)

    var fallbackCount = 0
    MockURLProtocol.response = { request in
      if request.url?.host == "huggingface.co" {
        return (503, Data("unavailable".utf8))
      }
      return (200, Data("{\"sha\":\"abc\"}".utf8))
    }
    let result: Revision = try await ASRDownloadSources.metadata(
      Revision.self, relativePath: "api/models/joe2643/test", session: mockSession,
      report: { event in
        if case .sourceFallback = event { fallbackCount += 1 }
      }
    )
    precondition(result.sha == "abc")
    precondition(fallbackCount == 1)

    // Files with an invalid checksum must follow the same retry owner.
    var corruptFallbackCount = 0
    let downloaded: String = try await ASRDownloadSources.withFallback(
      report: { event in
        if case .sourceFallback = event { corruptFallbackCount += 1 }
      }
    ) { host in
      if host == "huggingface.co" {
        throw URLError(.cannotDecodeContentData)
      }
      return "verified-model"
    }
    precondition(downloaded == "verified-model")
    precondition(corruptFallbackCount == 1)

    var cancelFallbackCount = 0
    do {
      let _: String = try await ASRDownloadSources.withFallback(
        report: { event in
          if case .sourceFallback = event { cancelFallbackCount += 1 }
        }
      ) { _ in throw CancellationError() }
      preconditionFailure("Cancellation must propagate")
    } catch is CancellationError {
      precondition(cancelFallbackCount == 0)
    }

    print("ASR source fallback: metadata, invalid file, and cancellation PASS")
  }
}
