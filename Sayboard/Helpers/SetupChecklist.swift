
// A recent extension callback can verify access; elapsed time does not prove
// that iOS revoked permission. Unknown must never be treated as denied.
enum KeyboardAccessEvidence: Equatable, Sendable {
  case confirmed
  case denied
  case unknown

  static func isRecentReport(at timestamp: Double, now: Double, maxAge: Double = 90) -> Bool {
    let age = now - timestamp
    return timestamp > 0 && age >= 0 && age <= maxAge
  }

  static func assess(
    at timestamp: Double,
    now: Double,
    fullAccess: Bool?,
    extensionGroupAvailable: Bool,
    appGroupAvailable: Bool
  ) -> Self {
    guard appGroupAvailable, extensionGroupAvailable, let fullAccess,
          Self.isRecentReport(at: timestamp, now: now) else { return .unknown }
    return fullAccess ? .confirmed : .denied
  }

  var statusText: String {
    switch self {
    case .confirmed: "Recently confirmed"
    case .denied: "Recently reported as disabled"
    case .unknown: "Not verified (not necessarily disabled)"
    }
  }
}


struct SetupChecklist: Equatable, Sendable {

  let microphoneGranted: Bool
  let keyboardAdded: Bool
  let fullAccessGranted: Bool
  let hasUsableModel: Bool

  var remainingCount: Int {
    [self.microphoneGranted, self.keyboardAdded, self.fullAccessGranted, self.hasUsableModel]
      .count { !$0 }
  }

  var isComplete: Bool {
    self.remainingCount == 0
  }
}
