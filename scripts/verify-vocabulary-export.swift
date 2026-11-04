import Foundation

@main
struct VerifyVocabularyExport {
  static func main() throws {
    let json = try PersonalVocabularyExport.encode(
      cantonese: ["世一|sai3 jat1": 3, "bad": 0],
      latin: ["en|brb": 4, "de|safe": 2],
      romanization: ["sidney": 8]
    )
    let root = try JSONSerialization.jsonObject(with: json) as! [String: Any]
    precondition(root["schemaVersion"] as? Int == 1)
    let cantonese = root["cantoneseSelections"] as! [String: Int]
    precondition(cantonese["世一|sai3 jat1"] == 3)
    precondition(cantonese["bad"] == nil)
    let latin = root["latinSelections"] as! [String: Int]
    precondition(latin["de|safe"] == 2)
    precondition(latin["en|brb"] == 4)
    precondition(String(decoding: json, as: UTF8.self).contains("schemaVersion"))
    print("Private aggregate vocabulary export verified")
  }
}
