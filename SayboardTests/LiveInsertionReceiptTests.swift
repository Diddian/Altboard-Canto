import Foundation
import Testing

@testable import Sayboard

@Suite("Live transcription insertion receipts")
struct LiveInsertionReceiptTests {
  @Test func firstClaimWinsAcrossControllerRecreation() throws {
    let folder = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }

    let token = UUID().uuidString
    #expect(!ExperimentalLiveTranscription.hasHostInsertionStarted(for: token, container: folder))
    #expect(ExperimentalLiveTranscription.claimHostInsertion(for: token, container: folder))
    #expect(ExperimentalLiveTranscription.hasHostInsertionStarted(for: token, container: folder))
    #expect(!ExperimentalLiveTranscription.claimHostInsertion(for: token, container: folder))

    // Another capture owns a separate receipt and is not blocked by the first.
    let next = UUID().uuidString
    #expect(!ExperimentalLiveTranscription.hasHostInsertionStarted(for: next, container: folder))
    #expect(ExperimentalLiveTranscription.claimHostInsertion(for: next, container: folder))
    #expect(ExperimentalLiveTranscription.hasHostInsertionStarted(for: next, container: folder))
  }

  @Test func invalidTokenOrMissingSharedStorageFailsClosed() {
    let valid = UUID().uuidString
    #expect(!ExperimentalLiveTranscription.claimHostInsertion(for: "not-a-uuid", container: nil))
    #expect(!ExperimentalLiveTranscription.claimHostInsertion(for: valid, container: nil))
    #expect(ExperimentalLiveTranscription.hasHostInsertionStarted(for: valid, container: nil))
  }
}
