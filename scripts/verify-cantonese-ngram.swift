import Foundation

@main
struct VerifyCantoneseNgram {
  static func main() {
    let lexicon: [String: [CantoneseNgramPiece]] = [
      "nei": [.init(text: "你", romanization: "nei5")],
      "dou": [.init(text: "都", romanization: "dou1")],
      "m": [.init(text: "唔", romanization: "m4")],
      "ng": [.init(text: "唔", romanization: "m4"), .init(text: "嗯", romanization: "ng5")],
      "sik": [.init(text: "識", romanization: "sik1"), .init(text: "色", romanization: "sik1")],
      "ho": [.init(text: "可", romanization: "ho2")],
      "hoh": [.init(text: "可", romanization: "ho2")],
      "nang": [.init(text: "能", romanization: "nang4")],
      "lang": [.init(text: "能", romanization: "nang4")],
      "ye": [.init(text: "耶", romanization: "je4")],
      "so": [.init(text: "穌", romanization: "sou1")],
      "sou": [.init(text: "穌", romanization: "sou1")],
    ]
    let counts = ["你都": 20, "都唔": 18, "唔識": 15, "都唔識": 12,
                  "你都唔": 10, "可能": 30, "耶穌": 12, "唔色": 0]
    func decode(_ code: String) -> [CantoneseNgramPiece] {
      CantoneseNgramDecoder.decode(
        code,
        choices: { lexicon[$0] ?? [] },
        frequency: { counts[$0] ?? 0 },
        wordFrequency: { counts[$0] ?? 0 }
      )
    }
    precondition(decode("neidoumsik").first?.text == "你都唔識", "Ranking failed")
    precondition(decode("neidoungsik").first?.text == "你都唔識", "ng alias failed")
    for code in ["honang", "hohnang", "holang", "hohlang"] {
      precondition(decode(code).contains { $0.text == "可能" }, "Missing \(code)")
    }
    precondition(decode("yesou").contains { $0.text == "耶穌" }, "Jesus spelling failed")
    precondition(decode("to12").isEmpty, "Invalid tone mix accepted")
    precondition(decode("x").isEmpty, "Incomplete syllable accepted")
    print("Cantonese N-gram decoder smoke tests passed")
  }
}
