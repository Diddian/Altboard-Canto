import Foundation
@main
enum VerifySchemePreference {
  static func main() {
    precondition(CantoneseSchemePreference.inferredScheme(input: "kui", canonical: "keoi5") == "sidney")
    precondition(CantoneseSchemePreference.inferredScheme(input: "keui", canonical: "keoi5") == "yale")
    precondition(CantoneseSchemePreference.inferredScheme(input: "keoi", canonical: "keoi5") == "plain")
    precondition(CantoneseSchemePreference.inferredScheme(input: "m", canonical: "m4") == nil)
    precondition(CantoneseSchemePreference.inferredScheme(input: "jau", canonical: "zau6") == "traditional")
    precondition(CantoneseSchemePreference.inferredScheme(input: "chaan", canonical: "caan4") == "traditional")
    precondition(CantoneseSchemePreference.preferred(["traditional": 5]) == "yale")
    precondition(CantoneseSchemePreference.preferred(["traditional": 5, "sidney": 2]) == "sidney")
    precondition(CantoneseSchemePreference.preferred(["traditional": 5, "plain": 10]) == nil)
    precondition(CantoneseSchemePreference.preferred(["sidney": 6]) == nil)
    precondition(CantoneseSchemePreference.preferred(["sidney": 10, "plain": 1, "yale": 1]) == "sidney")
    precondition(CantoneseSchemePreference.lookupOrder([:]) == ["plain", "yale", "sidney"])
    precondition(CantoneseSchemePreference.negativeParticleStyle(
      input: "sikngsik", canonical: "sik6 m4 sik6"
    ) == CantoneseSchemePreference.colloquialNgKey)
    precondition(CantoneseSchemePreference.negativeParticleStyle(
      input: "sikmsik", canonical: "sik6 m4 sik6"
    ) == CantoneseSchemePreference.canonicalMKey)
    precondition(CantoneseSchemePreference.negativeParticleStyle(
      input: "ngaan", canonical: "ngaan5"
    ) == nil)
    var evidence = [String: Int]()
    for _ in 0..<5 {
      evidence = CantoneseSchemePreference.recordingSelection(
        in: evidence, typed: "jau", canonical: "zau6"
      )
    }
    precondition(CantoneseSchemePreference.lookupOrder(evidence) == ["yale", "sidney", "plain"])
    for _ in 0..<12 {
      evidence = CantoneseSchemePreference.recordingSelection(
        in: evidence, typed: "kui", canonical: "keoi5"
      )
    }
    precondition(CantoneseSchemePreference.lookupOrder(evidence) == ["sidney", "yale", "plain"])
    for _ in 0..<22 {
      evidence = CantoneseSchemePreference.recordingSelection(
        in: evidence, typed: "keui", canonical: "keoi5"
      )
    }
    precondition(CantoneseSchemePreference.lookupOrder(evidence) == ["yale", "sidney", "plain"])
    for _ in 0..<60 {
      evidence = CantoneseSchemePreference.recordingSelection(
        in: evidence, typed: "keoi", canonical: "keoi5"
      )
    }
    precondition(CantoneseSchemePreference.lookupOrder(evidence) == ["plain", "yale", "sidney"],
                 "Recent Jyutping selections must replace old Yale evidence")
    precondition(evidence.values.reduce(0,+) < 70)
    var negation = [String: Int]()
    for _ in 0..<4 {
      negation = CantoneseSchemePreference.recordingSelection(
        in: negation, typed: "nghai", canonical: "m4 hai6"
      )
    }
    precondition(CantoneseSchemePreference.prefersColloquialNg(negation))
    for _ in 0..<7 {
      negation = CantoneseSchemePreference.recordingSelection(
        in: negation, typed: "mhai", canonical: "m4 hai6"
      )
    }
    precondition(!CantoneseSchemePreference.prefersColloquialNg(negation))
    let unchanged = CantoneseSchemePreference.recordingSelection(
      in: evidence, typed: "long", canonical: "lung4"
    )
    precondition(unchanged == evidence)

    let diagnostic = try! CantoneseSchemePreference.diagnosticJSON(
      counts: ["plain": 1, "yale": 9, "negative_ng": 4],
      candidateCounts: ["敏感文字|secret": 7, "示例": 3],
      groupAvailable: true, preferenceDataPresent: true,
      appVersion: "1.14.2", appBuild: "24",
      appCommit: "appSHA", keyboardCommit: "keyboardSHA",
      generatedAt: Date(timeIntervalSince1970: 0)
    )
    let report = try! JSONSerialization.jsonObject(with: diagnostic) as! [String: Any]
    let storage = report["storage"] as! [String: Any]
    let learned = report["romanization"] as! [String: Any]
    let candidates = report["candidate_learning"] as! [String: Any]
    let privacy = report["privacy"] as! [String: Any]
    precondition((report["schema_version"] as? Int) == 1)
    precondition((storage["status"] as? String) == "learning")
    precondition((learned["preferred_scheme"] as? String) == "undetermined")
    precondition((learned["total_weighted_evidence"] as? Int) == 14)
    precondition((candidates["stored_candidate_count"] as? Int) == 2)
    precondition((candidates["stored_selection_weight"] as? Int) == 10)
    precondition((privacy["candidate_words_included"] as? Bool) == false)
    let exported = String(decoding: diagnostic, as: UTF8.self)
    precondition(!exported.contains("敏感文字") && !exported.contains("secret"))
    precondition(!exported.contains("示例"))
    let unavailable = try! CantoneseSchemePreference.diagnosticJSON(
      counts: [:], candidateCounts: [:], groupAvailable: false,
      preferenceDataPresent: false, appVersion: "1.14.2", appBuild: "24",
      appCommit: "appSHA", keyboardCommit: "not reported",
      generatedAt: Date(timeIntervalSince1970: 0)
    )
    let fallback = try! JSONSerialization.jsonObject(with: unavailable) as! [String: Any]
    precondition((fallback["storage"] as? [String: Any])?["status"] as? String == "unavailable")
  }
}
