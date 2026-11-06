import Foundation

@main
struct VerifyLatinSpeechLearning {
  static func main() throws {
    let suite = "altboard.speech.learning." + UUID().uuidString
    guard let defaults = UserDefaults(suiteName: suite) else { fatalError("Missing defaults") }
    defer { defaults.removePersistentDomain(forName: suite) }

    func record(
      _ heard: String, _ intended: String, _ languages: [String]
    ) -> HistoryRecord {
      HistoryRecord(
        id: UUID(), date: Date(), duration: 2, transcription: heard,
        audioFileName: UUID().uuidString, originalASR: heard,
        userCorrection: intended, recognitionLanguages: languages
      )
    }
    let de = (0..<3).map { _ in record("ich binn heute da", "ich bin heute da", ["de"]) }
    let en = (0..<3).map { _ in record("helllo everyone", "hello everyone", ["en"]) }
    let ambiguous = (0..<4).map { _ in
      record("geschikt paket", "geschickt paket", ["de", "en"])
    }
    let caseOnly = (0..<4).map { _ in
      record("Hallo Zusammen", "Hallo zusammen", ["de"])
    }
    let rules = LatinSpeechCorrectionLearning.recurringRules(
      in: de + en + ambiguous + caseOnly
    )
    precondition(rules.count == 2)
    precondition(rules.contains {
      $0.language == "de" && $0.heard == "binn" && $0.intended == "bin"
    })
    precondition(rules.contains {
      $0.language == "en" && $0.heard == "helllo" && $0.intended == "hello"
    })
    precondition(LatinSpeechCorrectionLearning.recurringRules(in: de.prefix(2).map { $0 }).isEmpty)
    LatinSpeechCorrectionLearning.save(rules, defaults: defaults)
    precondition(LatinSpeechCorrectionLearning.read(defaults: defaults) == rules)
    precondition(LatinSpeechCorrectionLearning.apply(
      "ich binn heute da", languages: ["de"], defaults: defaults
    ) == "ich bin heute da")
    precondition(LatinSpeechCorrectionLearning.apply(
      "ich binnchen heute", languages: ["de"], defaults: defaults
    ) == "ich binnchen heute")
    precondition(LatinSpeechCorrectionLearning.apply(
      "ich binn heute da", languages: ["en"], defaults: defaults
    ) == "ich binn heute da")
    precondition(LatinSpeechCorrectionLearning.apply(
      "helllo everyone", languages: ["en"], defaults: defaults
    ) == "hello everyone")
    precondition(LatinSpeechCorrectionLearning.apply(
      "helllo everyone", languages: ["en", "de"], defaults: defaults
    ) == "helllo everyone")
    precondition(LatinSpeechCorrectionLearning.unambiguousLanguage(["de-DE"]) == "de")
    precondition(LatinSpeechCorrectionLearning.unambiguousLanguage(["yue"]) == nil)
    precondition(LatinSpeechCorrectionLearning.singleWordChange(
      heard: "This is pretty good", intended: "That seems pretty great", language: "en"
    ) == nil)
    precondition(LatinSpeechCorrectionLearning.singleWordChange(
      heard: "ja!", intended: "ja?", language: "de"
    ) == nil)
    let newRecord = de[0].withCorrection("ich bin heute da")
    precondition(newRecord.recognitionLanguages == ["de"])
    var data = try JSONSerialization.jsonObject(with: JSONEncoder().encode(newRecord))
      as! [String: Any]
    data.removeValue(forKey: "recognitionLanguages")
    let oldRecord = try JSONDecoder().decode(
      HistoryRecord.self, from: JSONSerialization.data(withJSONObject: data)
    )
    precondition(oldRecord.recognitionLanguages.isEmpty)
    print("Language-scoped repeated speech correction learning verified")
  }
}
