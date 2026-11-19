import Foundation

enum DictationCapturePolicy {
  enum Confirmation: Equatable {
    case waiting, confirmed, unavailable, timedOut
  }

  static let confirmationTimeout: TimeInterval = 2

  static func isPendingStart(startedAt: TimeInterval, now: TimeInterval) -> Bool {
    guard startedAt.isFinite, now.isFinite, startedAt > 0 else { return false }
    let elapsed = now - startedAt
    return elapsed >= 0 && elapsed < self.confirmationTimeout
  }

  static func canRejectUnacceptedRequest(
    activeToken: String?, recording: Bool, finalizing: Bool, ownsCapture: Bool
  ) -> Bool {
    activeToken == nil && !recording && !finalizing && !ownsCapture
  }

  static func shouldDeferRequestedStop(
    confirmation: Confirmation, awaitingConfirmation: Bool
  ) -> Bool {
    awaitingConfirmation && confirmation == .waiting
  }

  /// Engine startup alone does not prove that usable microphone frames arrived.
  /// Silent frames still confirm capture; signal amplitude is not an oracle.
  static func confirmation(
    sessionHealthy: Bool, ownsCapture: Bool,
    outputFrames: Int, elapsed: TimeInterval
  ) -> Confirmation {
    guard sessionHealthy, ownsCapture else { return .unavailable }
    if outputFrames > 0 { return .confirmed }
    guard elapsed.isFinite, elapsed >= 0, elapsed < self.confirmationTimeout else {
      return .timedOut
    }
    return .waiting
  }
}
