import Foundation
import Testing

@Suite("History correction learning")
struct SpeechCorrectionLearningTests {
  @Test func boundedSingleReplacement() {
    let pair = SpeechCorrectionLearning.pair(
      heard: "我唔系咁講", intended: "我唔係咁講"
    )
    #expect(pair != nil)
    #expect(pair?.heard != pair?.intended)
    #expect(pair?.heard.contains("系") == true)
    #expect(pair?.intended.contains("係") == true)
  }

  @Test func skipsStylisticRewritesAndEnglish() {
    #expect(SpeechCorrectionLearning.pair(
      heard: "The quick brown fox",
      intended: "A very different sentence about entirely new things"
    ) == nil)
    #expect(SpeechCorrectionLearning.pair(
      heard: "hello", intended: "hullo"
    ) == nil)
  }

  @Test func onlyThreeDistinctVerifiedRecordingsLearn() {
    func record(_ day: Int) -> HistoryRecord {
      HistoryRecord(
        id: UUID(),
        date: Date(timeIntervalSince1970: Double(day) * 86_400),
        duration: 4, transcription: "我唔系咁講",
        audioFileName: "clip-\(day).caf",
        originalASR: "我唔系咁講"
      ).withCorrection("我唔係咁講")
    }
    #expect(SpeechCorrectionLearning.recurringPairs(
      in: [record(1), record(2)]
    ).isEmpty)
    #expect(SpeechCorrectionLearning.recurringPairs(
      in: [record(1), record(2), record(3)]
    ).count == 1)
  }

  @Test func legacyHistoryStillDecodes() throws {
    let original = HistoryRecord(
      id: UUID(), date: Date(), duration: 3,
      transcription: "舊記錄", audioFileName: "old.caf"
    )
    let decoded = try JSONDecoder().decode(
      HistoryRecord.self, from: JSONEncoder().encode(original)
    )
    #expect(decoded.originalASR == nil)
    #expect(decoded.userCorrection == nil)
    #expect(decoded.displayedTranscription == "舊記錄")
  }
}
