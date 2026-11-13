/// Parked audio intent has exactly one owner and one restoration attempt.
struct AudioSessionRecoveryGate {
  private(set) var isParked = false

  mutating func park(sessionActive: Bool, capturing: Bool) -> Bool {
    guard sessionActive, !capturing, !self.isParked else { return false }
    self.isParked = true
    return true
  }

  mutating func cancel() { self.isParked = false }

  /// nil means no parked intent; false means a safety gate rejected it.
  mutating func take(
    allowed: Bool, captureFree: Bool, playbackFree: Bool, competingSessionFree: Bool
  ) -> Bool? {
    guard self.isParked else { return nil }
    self.isParked = false
    return allowed && captureFree && playbackFree && competingSessionFree
  }
}
