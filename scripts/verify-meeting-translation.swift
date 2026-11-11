import Foundation

@main
struct VerifyMeetingTranslationPolicy {
  static func main() {
    typealias P = MeetingTranslationPolicy
    precondition(P.chunks("").isEmpty)
    precondition(P.chunks("Hello").count == 1)
    precondition(P.chunks("Hello") == ["Hello"])
    let phrase = String(repeating: "Merhaba, arkadaşım nasılsın? ", count: 60)
      + String(repeating: "我今日真係好開心。", count: 25)
    let segments = P.chunks(phrase)
    precondition(segments.count > 5)
    precondition(segments.allSatisfy { !$0.isEmpty && $0.count <= P.maximumChunkCharacters })
    precondition(
      segments.joined().filter { !$0.isWhitespace }
        == phrase.filter { !$0.isWhitespace }
    )
    precondition(P.sourceFingerprint("Turkish") == P.sourceFingerprint("Turkish"))
    precondition(P.sourceFingerprint("Turkish") != P.sourceFingerprint("Cantonese"))
    precondition(!P.canResume(
      sourceFingerprint: "a", configurationKey: "yue",
      savedFingerprint: "b", savedConfigurationKey: "yue",
      processedChunks: 2, totalChunks: 5, savedTranslation: "A"
    ))
    precondition(!P.canResume(
      sourceFingerprint: "a", configurationKey: "yue",
      savedFingerprint: "a", savedConfigurationKey: "en",
      processedChunks: 2, totalChunks: 5, savedTranslation: "A"
    ))
    precondition(!P.canResume(
      sourceFingerprint: "a", configurationKey: "yue",
      savedFingerprint: "a", savedConfigurationKey: "yue",
      processedChunks: 6, totalChunks: 5, savedTranslation: "A"
    ))
    precondition(!P.canResume(
      sourceFingerprint: "a", configurationKey: "yue",
      savedFingerprint: "a", savedConfigurationKey: "yue",
      processedChunks: 2, totalChunks: 5, savedTranslation: nil
    ))
    precondition(P.canResume(
      sourceFingerprint: "a", configurationKey: "yue",
      savedFingerprint: "a", savedConfigurationKey: "yue",
      processedChunks: 2, totalChunks: 5, savedTranslation: "A"
    ))
    precondition(P.canResume(
      sourceFingerprint: "a", configurationKey: "yue",
      savedFingerprint: "a", savedConfigurationKey: "yue",
      processedChunks: 0, totalChunks: 5, savedTranslation: nil
    ))
    precondition(!P.canResume(
      sourceFingerprint: "a", configurationKey: "yue",
      savedFingerprint: "a", savedConfigurationKey: "yue",
      processedChunks: 2, totalChunks: 5, savedTranslation: "  \n  "
    ))
    precondition(Array(P.pendingChunkIndices(totalChunks: 4, startingAt: 2)!) == [2, 3])
    precondition(P.pendingChunkIndices(totalChunks: 4, startingAt: 4)?.isEmpty == true)
    precondition(P.pendingChunkIndices(totalChunks: 4, startingAt: -1) == nil)
    precondition(P.pendingChunkIndices(totalChunks: 4, startingAt: 5) == nil)
    // A saved prefix must survive cancellation; resumption only processes its
    // missing suffix, even when the first outstanding section is retried.
    let source = ["A", "B", "C", "D"]
    var saved = ["translated A", "translated B"]
    var cursor = 2
    for index in P.pendingChunkIndices(totalChunks: source.count, startingAt: cursor)! {
      if index == 2 { break } // cancelled before accepting the next section
    }
    precondition(cursor == 2 && saved.count == 2)
    for index in P.pendingChunkIndices(totalChunks: source.count, startingAt: cursor)! {
      saved.append("translated " + source[index])
      cursor = index + 1
    }
    precondition(cursor == 4 && saved == ["translated A", "translated B", "translated C", "translated D"])
    precondition(P.combined(nil, next: "   粵語內容  ") == "粵語內容")
    precondition(P.combined("粵語內容", next: " 下一段 ") == "粵語內容\n下一段")
    print("meeting translation policy: bounded segmentation, resume and original fidelity PASS")
  }
}
