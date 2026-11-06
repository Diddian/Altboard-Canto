import Foundation

@main
struct VerifyVocabularyExport {
  static func main() throws {
    let json = try PersonalVocabularyExport.encode(
      cantonese: ["世一|sai3 jat1": 3, "bad": 0],
      latin: ["en|brb": 4, "de|safe": 2],
      romanization: ["sidney": 8],
      confirmedChinese: ["佢": 5],
      shapes: ["cangjie|佢": 3, "stroke|佢": 2],
      shapeGenerations: ["cangjie.3": 4],
      strokePrefixes: ["nm|佢": 2],
      manualCorrections: [
        .init(language: "yue", heard: "餵你", intended: "喂你"),
        .init(language: "en", heard: "helllo", intended: "hello")
      ]
    )
    let root = try JSONSerialization.jsonObject(with: json) as! [String: Any]
    precondition(root["schemaVersion"] as? Int == 3)
    precondition((root["confirmedChineseWords"] as? [String: Int])?["佢"] == 5)
    precondition((root["shapeSelections"] as? [String: Int])?["stroke|佢"] == 2)
    precondition((root["shapeGenerationPreferences"] as? [String: Int])?["cangjie.3"] == 4)
    precondition((root["strokePrefixSelections"] as? [String: Int])?["nm|佢"] == 2)
    precondition((root["manualSpeechCorrections"] as? [[String: String]])?.count == 2)
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
