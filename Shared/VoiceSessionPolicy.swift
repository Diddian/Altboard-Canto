import Foundation

/// A renewable visibility lease contains no host, field or typing information.
/// It expires if iOS suspends or terminates the keyboard without a hide callback.
enum VoiceSessionPolicy {
  static let keyboardRenewalInterval: TimeInterval = 15
  static let keyboardLeaseDuration: TimeInterval = 45

  struct KeyboardActivity: Codable, Equatable, Sendable {
    let owner: UUID
    let updatedAt: TimeInterval
    let visible: Bool

    func isActive(at now: TimeInterval) -> Bool {
      self.visible && self.updatedAt.isFinite && now.isFinite
        && self.updatedAt > 0 && now >= self.updatedAt
        && now - self.updatedAt < VoiceSessionPolicy.keyboardLeaseDuration
    }

    func canBeEnded(by owner: UUID) -> Bool { self.owner == owner }

    func applyingEnd(_ end: KeyboardActivity?) -> KeyboardActivity {
      guard let end, !end.visible, end.owner == self.owner,
            end.updatedAt >= self.updatedAt else { return self }
      return end
    }
  }

  static func isReady(active: Bool, heartbeat: TimeInterval, now: TimeInterval) -> Bool {
    active && heartbeat.isFinite && now.isFinite && heartbeat > 0
      && now >= heartbeat && now - heartbeat <= 3
  }

  enum Decision: Equatable, Sendable {
    case active(checkAfter: TimeInterval?)
    case unlimited
    case idle(deadline: TimeInterval)
    case expired
  }

  struct IdleTimer: Sendable {
    private(set) var idleSince: TimeInterval?

    mutating func reset() { self.idleSince = nil }

    mutating func evaluate(
      now: TimeInterval, timeout: TimeInterval?, appForeground: Bool,
      capturing: Bool, keyboard: KeyboardActivity?
    ) -> Decision {
      guard now.isFinite, now > 0 else {
        self.idleSince = nil
        return .active(checkAfter: 1)
      }
      if appForeground || capturing {
        self.idleSince = nil
        return .active(checkAfter: nil)
      }
      if let keyboard, keyboard.isActive(at: now) {
        self.idleSince = nil
        return .active(checkAfter: max(0.1,
          keyboard.updatedAt + VoiceSessionPolicy.keyboardLeaseDuration - now))
      }
      guard let timeout, timeout.isFinite, timeout >= 0 else {
        self.idleSince = nil
        return .unlimited
      }
      if let since = self.idleSince {
        if now < since { self.idleSince = now }
      } else {
        self.idleSince = now
      }
      let deadline = (self.idleSince ?? now) + timeout
      return now >= deadline ? .expired : .idle(deadline: deadline)
    }
  }
}
