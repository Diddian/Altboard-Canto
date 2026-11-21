import Foundation

@main
struct DictationStartupChecks {
  static func main() {
    let token = UUID().uuidString
    let other = UUID().uuidString
    let request = DictationStartupPolicy.Request(token: token, startedAt: 100)
    var checks = 0
    func check(_ condition: Bool) {
      precondition(condition)
      checks += 1
    }
    func decision(
      elapsed: TimeInterval = 0, current: String? = nil, cancelled: Bool = false,
      visible: Bool = true, acknowledged: Bool = false, frames: Bool = false,
      heartbeat: Bool = false, progress: Bool = false, stopped: Bool = false,
      loading: Bool = false
    ) -> DictationStartupPolicy.Decision {
      DictationStartupPolicy.decision(
        request: request, currentToken: current ?? token, cancelled: cancelled,
        visible: visible, captureAcknowledged: acknowledged, recordedFrames: frames,
        recentAudioHeartbeat: heartbeat, currentProgress: progress,
        stopRequested: stopped, modelLoading: loading, now: 100 + elapsed
      )
    }

    check(decision() == .waiting)
    check(decision(elapsed: 8) == .waiting)
    check(decision(elapsed: 14.999) == .waiting)
    check(decision(elapsed: 15) == .expired)
    check(decision(elapsed: 300, visible: false) == .paused)
    check(decision(elapsed: 300, acknowledged: true) == .finished)
    check(decision(elapsed: 300, current: other) == .finished)
    check(decision(elapsed: 300, cancelled: true) == .finished)
    check(decision(elapsed: 300, progress: true) == .processing)
    check(decision(elapsed: 300, stopped: true) == .processing)
    check(decision(elapsed: 8, frames: true, heartbeat: true) == .waiting)
    check(decision(elapsed: 15, frames: true, heartbeat: true) == .finishCapturedSpeech)
    check(decision(elapsed: 15, visible: false, frames: true, heartbeat: true) == .paused)
    check(decision(elapsed: 15, frames: true) == .finishCapturedSpeech)
    check(decision(elapsed: 8, frames: true) == .waiting)
    check(decision(elapsed: 60, visible: false, frames: true) == .paused)
    check(decision(elapsed: 60, frames: true, progress: true) == .processing)
    check(decision(elapsed: 15, heartbeat: true) == .expired)
    check(decision(elapsed: 15, loading: true) == .expired)
    check(decision(elapsed: 15, heartbeat: true, loading: true) == .waiting)
    check(decision(elapsed: 179.999, heartbeat: true, loading: true) == .waiting)
    check(decision(elapsed: 180, heartbeat: true, loading: true) == .expired)
    check(decision(elapsed: .nan) == .expired)
    check(decision(elapsed: -.infinity) == .expired)
    check(decision(elapsed: -1) == .expired)
    check(decision(elapsed: .nan, frames: true, heartbeat: true) == .finishCapturedSpeech)

    let suite = "altboard.test.startup." + UUID().uuidString
    guard let defaults = UserDefaults(suiteName: suite) else { fatalError("No test defaults") }
    defer { defaults.removePersistentDomain(forName: suite) }
    check(DictationStartupPolicy.request(for: token, defaults: defaults) == nil)
    check(!DictationStartupPolicy.begin(token: "invalid", now: 100, defaults: defaults))
    check(!DictationStartupPolicy.begin(token: token, now: .nan, defaults: defaults))
    check(DictationStartupPolicy.begin(token: token, now: 100, defaults: defaults))
    defaults.synchronize()
    guard let reopened = UserDefaults(suiteName: suite) else { fatalError("No reopened defaults") }
    check(DictationStartupPolicy.request(for: token, defaults: reopened) == request)
    check(!DictationStartupPolicy.begin(token: token, now: 112, defaults: reopened))
    check(DictationStartupPolicy.request(for: token, defaults: reopened)?.startedAt == 100)
    check(DictationStartupPolicy.begin(token: other, now: 200, defaults: defaults))
    DictationStartupPolicy.clear(matching: token, defaults: defaults)
    check(DictationStartupPolicy.request(for: other, defaults: defaults)?.startedAt == 200)
    check(DictationStartupPolicy.request(for: token, defaults: defaults) == nil)
    DictationStartupPolicy.clear(matching: other, defaults: defaults)
    check(DictationStartupPolicy.request(for: other, defaults: defaults) == nil)
    print("Dictation startup: \(checks) checks passed")
  }
}
