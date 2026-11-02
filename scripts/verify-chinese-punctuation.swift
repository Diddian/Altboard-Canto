import Foundation

@main
enum VerifyChinesePunctuation {
  static func main() {
    let cases: [(String, String)] = [
      ("", "「"), ("你好", "「"),
      ("佢話「", "」"), ("佢話「你好", "」"),
      ("佢話「你好」", "「"),
      ("佢話「『係呀』", "」"),
      ("佢話「你好」\n再講", "「"),
      ("佢話」你好", "「"),
      ("佢話「再「", "」"),
      ("佢話「再「完」", "」"),
    ]
    for (context, expected) in cases {
      precondition(ChinesePunctuationPolicy.nextCornerQuote(after: context) == expected,
                   "Quote mismatch for \(context)")
    }
    print("CJK quote context safety: PASS (\(cases.count) cases)")
  }
}
