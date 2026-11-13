@main
struct AudioSessionRecoveryChecks {
  static func main() {
    var gate = AudioSessionRecoveryGate()
    precondition(!gate.park(sessionActive: false, capturing: false))
    precondition(!gate.park(sessionActive: true, capturing: true))
    precondition(gate.park(sessionActive: true, capturing: false))
    precondition(!gate.park(sessionActive: true, capturing: false))
    precondition(gate.take(allowed: true, captureFree: true,
                          playbackFree: true, competingSessionFree: true) == true)
    precondition(!gate.isParked)
    precondition(gate.take(allowed: true, captureFree: true,
                          playbackFree: true, competingSessionFree: true) == nil)
    precondition(gate.park(sessionActive: true, capturing: false))
    gate.cancel()
    precondition(gate.take(allowed: true, captureFree: true,
                          playbackFree: true, competingSessionFree: true) == nil)
    for state in 0..<4 {
      precondition(gate.park(sessionActive: true, capturing: false))
      let take = gate.take(
        allowed: state != 0, captureFree: state != 1,
        playbackFree: state != 2, competingSessionFree: state != 3
      )
      precondition(take == false && !gate.isParked)
    }
    precondition(LiveWarmupMemoryPolicy.requiredAvailableMB(
      requirementMB: 4_000, wantsLive: true) == 2_400)
    precondition(!LiveWarmupMemoryPolicy.allowsWarmup(
      availableMB: 2_399, requirementMB: 4_000, wantsLive: true))
    precondition(LiveWarmupMemoryPolicy.allowsWarmup(
      availableMB: 2_400, requirementMB: 4_000, wantsLive: true))
    precondition(!LiveWarmupMemoryPolicy.allowsWarmup(
      availableMB: 4_511, requirementMB: 4_000, wantsLive: false))
    precondition(LiveWarmupMemoryPolicy.allowsWarmup(
      availableMB: 4_512, requirementMB: 4_000, wantsLive: false))
    print("Audio recovery and memory admission: PASS")
  }
}
