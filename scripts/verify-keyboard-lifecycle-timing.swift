import Foundation

@main
struct KeyboardLifecycleTimingChecks {
  static func main() {
    typealias T = KeyboardLifecycleTiming
    let review = T.analyze([
      .init(1_000, .loadViewStarting, session: "cold"),
      .init(1_080, .hostingMounted, session: "cold"),
      .init(1_100, .willAppear, session: "cold"),
      .init(1_135, .didAppear, session: "cold"),
      .init(1_240, .renderCheckpoint, session: "cold"),
      .init(1_250, .willDisappear, session: "cold"),
      .init(2_000, .willAppear, session: "cold"),
      .init(2_070, .renderCheckpoint, session: "cold"),
      .init(2_071, .renderSuspicious, session: "cold"),
      .init(2_130, .didAppear, session: "cold"),
      .init(2_200, .willDisappear, session: "cold"),
      .init(3_000, .willAppear, session: "other"),
      .init(3_020, .didAppear, session: "other"),
      .init(3_100, .renderCheckpoint, session: "cold"),
      .init(3_200, .renderCheckpoint, session: "other")
    ])
    precondition(review.appearanceCount == 3)
    precondition(review.didAppearCount == 3)
    precondition(review.checkpointCount == 3)
    precondition(review.suspiciousAppearanceCount == 1)
    precondition(review.coldMountCount == 1)
    precondition(review.p95ColdLoadToMountMs == 80)
    precondition(review.p95AppearanceToCheckpointMs == 200)
    precondition(review.recentAppearances[0].checkpointDelayMs == 140)
    precondition(review.recentAppearances[1].checkpointDelayMs == 70)
    precondition(review.recentAppearances[2].checkpointDelayMs == 200)
    precondition(review.recentAppearances[2].didAppearDelayMs == 20)

    // Partial logs, process restarts, missing events, and stale events must
    // never fabricate zero-delay activation or associate another session.
    let partial = T.analyze([
      .init(10, .loadViewStarting, session: "first"),
      .init(20, .hostingMounted, session: "second"),
      .init(100, .willAppear, session: "first"),
      .init(120, .willDisappear, session: "first"),
      .init(130, .renderCheckpoint, session: "first"),
      .init(200, .didAppear, session: "second"),
      .init(-1, .willAppear, session: "invalid"),
      .init(61_000, .hostingMounted, session: "first")
    ])
    precondition(partial.appearanceCount == 1)
    precondition(partial.didAppearCount == 0)
    precondition(partial.checkpointCount == 0)
    precondition(partial.coldMountCount == 0)
    precondition(partial.p95ColdLoadToMountMs == nil)
    precondition(partial.p95AppearanceToCheckpointMs == nil)

    // A slow but valid activation must remain in p95, never be replaced by a
    // zero or omitted as a "normal" event.
    let slow = T.analyze([
      .init(0, .willAppear, session: "slow"),
      .init(21_000, .renderCheckpoint, session: "slow")
    ])
    precondition(slow.p95AppearanceToCheckpointMs == 21_000)
    print("Keyboard lifecycle timing: session isolation, missing/slow phases PASS")
  }
}
