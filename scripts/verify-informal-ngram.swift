import Foundation

@main
struct VerifyInformalNgrams {
  static func main() {
    precondition(InformalNgramPolicy.tokens(in: "Ich checke das") == ["ich", "checke", "das"])
    precondition(InformalNgramPolicy.preceding(in: "Ich che", current: "che") == ["ich"])
    precondition(InformalNgramPolicy.preceding(in: "Das ist sa", current: "sa") == ["das", "ist"])
    precondition(InformalNgramPolicy.histories(for: ["das", "ist"]) == ["das ist", "ist"])
    precondition(InformalNgramPolicy.tokens(in: "Ich. Digga") == ["digga"])
    precondition(InformalNgramPolicy.tokens(in: "我今日好 tired") == ["日", "好", "tired"])
    precondition(InformalNgramPolicy.preceding(in: "你好  brb", current: "brb") == ["你", "好"])
    precondition(InformalNgramPolicy.tokens(in: "Das ist safe!").isEmpty)
    precondition(InformalNgramPolicy.tokens(in: nil).isEmpty)
    print("Informal multilingual context tokenization verified")
  }
}
