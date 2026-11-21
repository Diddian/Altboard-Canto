import Foundation

@main
struct VoiceSessionChecks {
  static func main() {
    var checks = 0
    func check(_ condition: @autoclosure () -> Bool, _ message: String) {
      precondition(condition(), message)
      checks += 1
    }
    let owner = UUID()
    let other = UUID()
    let active = VoiceSessionPolicy.KeyboardActivity(owner: owner, updatedAt: 1_000, visible: true)
    check(active.isActive(at: 1_044), "Visible keyboard lease must cover its renewal interval")
    check(!active.isActive(at: 1_045), "A killed keyboard must not keep the session alive forever")
    check(!active.isActive(at: 999), "Future timestamps must not extend activity")
    check(!active.isActive(at: .nan), "Invalid clocks must not create a visibility lease")
    check(active.canBeEnded(by: owner), "The owning view can end its lease")
    check(!active.canBeEnded(by: other), "A previous view cannot end a newer view's lease")
    let hidden = VoiceSessionPolicy.KeyboardActivity(owner: owner, updatedAt: 1_010, visible: false)
    check(!active.applyingEnd(hidden).isActive(at: 1_010), "Hiding the current view ends activity")
    let oldHide = VoiceSessionPolicy.KeyboardActivity(owner: other, updatedAt: 1_020, visible: false)
    check(active.applyingEnd(oldHide).isActive(at: 1_020), "An older view's late hide must not overwrite the active view")
    let renewed = VoiceSessionPolicy.KeyboardActivity(owner: owner, updatedAt: 1_030, visible: true)
    check(renewed.applyingEnd(hidden).isActive(at: 1_030), "A completed hide cannot revoke later activity")
    check(try! JSONDecoder().decode(VoiceSessionPolicy.KeyboardActivity.self,
      from: JSONEncoder().encode(renewed)) == renewed, "Lease survives App Group encoding")

    var idle = VoiceSessionPolicy.IdleTimer()
    func evaluate(_ now: TimeInterval, foreground: Bool = false, capture: Bool = false,
                  keyboard: VoiceSessionPolicy.KeyboardActivity? = nil,
                  timeout: TimeInterval? = 900) -> VoiceSessionPolicy.Decision {
      idle.evaluate(now: now, timeout: timeout, appForeground: foreground,
        capturing: capture, keyboard: keyboard)
    }
    check(evaluate(1_000, foreground: true) == .active(checkAfter: nil), "Foreground app pauses idle timeout")
    check(evaluate(90_000, foreground: true) == .active(checkAfter: nil), "Foreground time never consumes idle time")
    check(evaluate(90_000, capture: true) == .active(checkAfter: nil), "Capture cannot be cut off by idle timeout")
    check(evaluate(1_000, keyboard: active) == .active(checkAfter: 45), "Visible keyboard pauses timeout")
    check(evaluate(1_030, keyboard: renewed) == .active(checkAfter: 45), "Renewal extends keyboard visibility")
    check(evaluate(1_075, keyboard: renewed) == .idle(deadline: 1_975), "Expired lease starts the configured idle period")
    check(evaluate(1_974) == .idle(deadline: 1_975), "The original deadline must not drift on status pings")
    check(evaluate(1_975) == .expired, "Stop at the actual idle deadline")
    check(evaluate(1_975, capture: true) == .active(checkAfter: nil), "A simultaneous capture wins over expiry")
    check(evaluate(2_000) == .idle(deadline: 2_900), "Finishing capture starts a fresh idle period")
    check(evaluate(2_899, foreground: true) == .active(checkAfter: nil), "Reopening the app cancels its countdown")
    check(evaluate(3_000) == .idle(deadline: 3_900), "Leaving the app restarts idle time")
    check(evaluate(3_100, timeout: nil) == .unlimited, "Never keeps the explicit opt-in session")
    check(evaluate(400_000, timeout: nil) == .unlimited, "Never does not acquire a hidden deadline")
    check(evaluate(400_000, timeout: 300) == .idle(deadline: 400_300), "Changing from Never uses the chosen timeout")
    idle.reset()
    check(evaluate(400_010, timeout: 3_600) == .idle(deadline: 403_610), "Changing timed settings resets the idle deadline")
    check(evaluate(1_000) == .idle(deadline: 1_900), "Clock rollback must not create an unbounded deadline")

    check(VoiceSessionPolicy.isReady(active: true, heartbeat: 1_000, now: 1_003), "Recent real audio marks readiness")
    check(!VoiceSessionPolicy.isReady(active: false, heartbeat: 1_000, now: 1_001), "Heartbeat cannot arm a stopped session")
    check(!VoiceSessionPolicy.isReady(active: true, heartbeat: 1_000, now: 1_004), "Persisted flags cannot prove live audio")
    check(!VoiceSessionPolicy.isReady(active: true, heartbeat: 1_001, now: 1_000), "Future heartbeat is not readiness")
    check(!VoiceSessionPolicy.isReady(active: true, heartbeat: .nan, now: 1_000), "Invalid heartbeat is not readiness")
    print("Voice session policy: \(checks) checks passed")
  }
}
