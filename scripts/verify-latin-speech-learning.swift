import Foundation
@main
enum VerifyLatinSpeechLearning {
  static func main() {
    let old = HistoryRecord(
      id: UUID(), date: Date(), duration: 2,
      transcription: "test", audioFileName: "fixture.caf",
      originalASR: "original", userCorrection: "edited"
    )
    precondition(old.displayedTranscription == "edited")
    precondition(old.withCorrection(nil).displayedTranscription == "test")
    // The #84 record has no language-producer field.
    precondition(LatinSpeechCorrectionLearning.recurringRules(in: [old]).isEmpty)
    print("Baseline history compatibility and inactive Latin learning passed")
  }
}
