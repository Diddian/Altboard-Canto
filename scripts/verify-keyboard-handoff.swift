import Foundation

@main
struct VerifyKeyboardHandoff {
  static func main() {
    typealias A = KeyboardHandoffAnalyzer
    let changed = A.analyze([
      .init(1_000, .hostMis, remembersSelection: false),
      .init(1_138, .hostOther, remembersSelection: false)
    ], nowMs: 7_000)
    precondition(changed.count == 1)
    precondition(changed[0].outcome == .modeChangedAwayBeforeLoad)
    precondition(changed[0].changeAwayDelayMs == 138)

    let mounted = A.analyze([
      .init(10_000, .hostMis, remembersSelection: true),
      .init(10_010, .extensionStarting),
      .init(10_075, .extensionMounted)
    ], nowMs: 15_000)
    precondition(mounted[0].outcome == .mountedObserved)
    precondition(mounted[0].mountDelayMs == 75)

    let partial = A.analyze([
      .init(20_000, .hostMis, remembersSelection: false),
      .init(20_100, .extensionStarting)
    ], nowMs: 25_000)
    precondition(partial[0].outcome == .loadStartedOnly)

    let noEvents: [A.Signal] = [.init(30_000, .hostMis, remembersSelection: false)]
    precondition(A.analyze(noEvents, nowMs: 30_200)[0].outcome == .awaitingEvidence)
    precondition(A.analyze(noEvents, nowMs: 35_000)[0].outcome == .launchNotObserved)

    let deduplicated = A.analyze([
      .init(40_000, .hostMis, remembersSelection: false),
      .init(40_100, .hostMis, remembersSelection: false),
      .init(40_200, .hostOther, remembersSelection: true),
      .init(40_400, .extensionMounted)
    ], nowMs: 45_000)
    precondition(deduplicated.count == 1)
    precondition(deduplicated[0].outcome == .mountedObserved)

    let reused = A.analyze([
      .init(49_800, .extensionAppearing),
      .init(50_000, .hostMis, remembersSelection: true)
    ], nowMs: 55_000)
    precondition(reused[0].outcome == .appearanceObserved)
    print("keyboard-handoff checks passed")
  }
}
