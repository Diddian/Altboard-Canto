import Foundation

@main
enum VerifyVocabularyExport {
  static func main() throws {
    let json = try PersonalVocabularyExport.encode(
      selections: ["佢|keoi5": 4, "bad": 0, "好|hou2": -1],
      romanization: ["sidney": 8, "plain": 3],
      corrections: [
        .init(language: "yue", heard: "餵你", intended: "喂你"),
        .init(language: "en", heard: "secret", intended: "example")
      ],
      version: "1.14", build: "84", commit: "fixture",
      keyboardCommit: "baseline"
    )
    let root = try JSONSerialization.jsonObject(with: json) as! [String: Any]
    precondition(root["schemaVersion"] as? Int == 1)
    precondition(root["appCommit"] as? String == "fixture")
    let selected = root["selections"] as! [String: Int]
    precondition(selected["佢|keoi5"] == 4)
    precondition(selected["bad"] == nil && selected["好|hou2"] == nil)
    let corrections = root["manualSpeechCorrections"] as! [[String: String]]
    precondition(corrections.count == 1)
    precondition(corrections[0]["language"] == "yue")
    let unavailable = root["unavailable"] as! [String]
    precondition(unavailable.contains("laterLatinLearning"))
    precondition(!String(decoding: json, as: UTF8.self).contains("transcript"))
    print("Explicit selection and correction export schema passed")
  }
}
