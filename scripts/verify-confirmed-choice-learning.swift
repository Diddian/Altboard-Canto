import Foundation

@main
struct VerifyConfirmedChoiceLearning {
  static func main() {
    let suite = "altboard.learning.test." + UUID().uuidString
    guard let defaults = UserDefaults(suiteName: suite) else { fatalError("No test defaults") }
    defer { defaults.removePersistentDomain(forName: suite) }

    precondition(!ConfirmedChoiceLearning.rememberConfirmedChinese("hello", defaults: defaults))
    precondition(!ConfirmedChoiceLearning.rememberConfirmedChinese("", defaults: defaults))
    precondition(ConfirmedChoiceLearning.chineseCounts(defaults: defaults).isEmpty)
    precondition(ConfirmedChoiceLearning.rememberConfirmedChinese("佢", defaults: defaults))
    precondition(ConfirmedChoiceLearning.rememberConfirmedChinese("佢", defaults: defaults))
    precondition(ConfirmedChoiceLearning.rememberConfirmedChinese("の", defaults: defaults))
    precondition(ConfirmedChoiceLearning.rememberConfirmedChinese("食花生", defaults: defaults))
    let seen = ConfirmedChoiceLearning.chineseCounts(defaults: defaults)
    precondition(seen["佢"] == 2 && seen["の"] == 1 && seen["食花生"] == 1)
    precondition(ConfirmedChoiceLearning.chinesePreference("佢", counts: seen) == 2)

    var counts: [String: Int] = ["old": 200, "rare": 1]
    counts = ConfirmedChoiceLearning.increment(
      "new", in: counts, maximum: 300, trimAt: 20, retain: 10, ageAtTotal: 150
    )
    precondition(counts["old"] == 100 && counts["new"] == 1 && counts["rare"] == nil)
    var bounded: [String: Int] = [:]
    for index in 0..<16 {
      bounded = ConfirmedChoiceLearning.increment(
        "word-\(index)", in: bounded, trimAt: 12, retain: 8, ageAtTotal: 99999
      )
    }
    precondition(bounded.count <= 12)
    let unchanged = ConfirmedChoiceLearning.increment("", in: bounded)
    precondition(unchanged == bounded)
    precondition(ConfirmedChoiceLearning.chinesePreference("none", counts: seen) == 0)
    // This helper is CI-only: the baseline keyboard never calls it.
    precondition(ConfirmedChoiceLearning.chineseCounts(defaults: defaults).count <= 12)
    print("Confirmed selection learning verified")
  }
}
