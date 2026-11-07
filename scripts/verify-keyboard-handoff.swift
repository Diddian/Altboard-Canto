import Foundation

@main
struct VerifyKeyboardHandoff {
  static func main() {
    typealias A = KeyboardHandoffAnalyzer
    let changed = A.analyze([
      .init(1_000, .hostLanguageHint, remembersSelection: false, activationID: "normal1"),
      .init(1_132, .hostOther, remembersSelection: false, activationID: "normal1")
    ], nowMs: 7_000)
    precondition(changed.count == 1)
    precondition(changed[0].outcome == .modeChangedAwayBeforeLoad)
    precondition(changed[0].changeAwayDelayMs == 132)

    // Real device regression: remembered multilingual hint, focus changes to Normal,
    // and extension mounts after Normal receives focus.
    let crossed = A.analyze([
      .init(10_000, .hostLanguageHint, remembersSelection: true, activationID: "remembered1"),
      .init(12_575, .fieldEnded, remembersSelection: true, activationID: "remembered1"),
      .init(12_579, .hostOther, remembersSelection: false, activationID: "normal2"),
      .init(12_589, .hostLanguageHint, remembersSelection: false, activationID: "normal2"),
      .init(12_815, .extensionStarting, sessionID: "extension2"),
      .init(12_864, .extensionMounted, sessionID: "extension2")
    ], nowMs: 17_000)
    precondition(crossed.count == 2)
    precondition(crossed[0].outcome == .launchNotObserved)
    precondition(crossed[0].mountDelayMs == nil)
    precondition(crossed[0].focusEndedAfterMs == 2_575)
    precondition(crossed[1].outcome == .extensionDetectedFieldUnconfirmed)
    precondition(crossed[1].extensionStage == .mounted)
    precondition(crossed[1].extensionSessionID == "extension2")
    precondition(crossed[1].mountDelayMs == 275)

    let started = A.analyze([
      .init(20_000, .hostLanguageHint, remembersSelection: true, activationID: "remembered3"),
      .init(20_100, .extensionStarting, sessionID: "launch3")
    ], nowMs: 25_000)
    precondition(started[0].outcome == .extensionDetectedFieldUnconfirmed)
    precondition(started[0].extensionStage == .started)

    let pending = A.analyze([
      .init(30_000, .hostLanguageHint, remembersSelection: false, activationID: "normal4")
    ], nowMs: 30_200)
    precondition(pending[0].outcome == .awaitingEvidence)
    precondition(A.analyze([
      .init(30_000, .hostLanguageHint, remembersSelection: false, activationID: "normal4")
    ], nowMs: 35_000)[0].outcome == .launchNotObserved)

    let deduplicated = A.analyze([
      .init(40_000, .hostLanguageHint, remembersSelection: false, activationID: "normal5"),
      .init(40_080, .hostLanguageHint, remembersSelection: false, activationID: "normal5"),
      .init(40_100, .hostOther, remembersSelection: true, activationID: "remembered6"),
      .init(40_200, .extensionMounted, sessionID: "session6")
    ], nowMs: 45_000)
    precondition(deduplicated.count == 1)
    precondition(deduplicated[0].outcome == .launchNotObserved)
    precondition(deduplicated[0].extensionStage == nil)

    // Legacy samples without activation IDs cannot safely identify fields.
    precondition(A.analyze([
      .init(49_000, .hostLanguageHint, remembersSelection: true),
      .init(49_100, .extensionMounted)
    ], nowMs: 54_000).isEmpty)
    // Other-language mode hints cannot be treated as Altboard handoffs.
    precondition(A.analyze([
      .init(55_000, .hostOther, remembersSelection: false, activationID: "other7"),
      .init(55_100, .extensionStarting, sessionID: "unrelated")
    ], nowMs: 60_000).isEmpty)
    print("keyboard-handoff checks passed")
  }
}
