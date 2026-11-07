
import Foundation

extension SharedSettings {

  var onboardingPracticeProcessID: Int? {
    get {
      let pid = self.defaults.integer(forKey: SharedKey.onboardingPracticePid)
      return pid > 0 ? pid : nil
    }
    nonmutating set {
      self.defaults.set(newValue ?? 0, forKey: SharedKey.onboardingPracticePid)
      self.defaults.set(newValue == nil ? 0 : CFAbsoluteTimeGetCurrent(), forKey: SharedKey.onboardingPracticeAt)
    }
  }

  /// Only the in-app keyboard selection field uses this marker. It must not
  /// activate microphone-practice hints on the keyboard.
  var onboardingKeyboardTestProcessID: Int? {
    get {
      let pid = self.defaults.integer(forKey: SharedKey.onboardingKeyboardTestPid)
      return pid > 0 ? pid : nil
    }
    nonmutating set {
      self.defaults.set(newValue ?? 0, forKey: SharedKey.onboardingKeyboardTestPid)
      self.defaults.set(newValue == nil ? 0 : CFAbsoluteTimeGetCurrent(),
        forKey: SharedKey.onboardingKeyboardTestAt)
    }
  }

  var isMicHintDismissed: Bool {
    get { self.defaults.bool(forKey: SharedKey.micHintDismissed) }
    nonmutating set { self.defaults.set(newValue, forKey: SharedKey.micHintDismissed) }
  }

  func isOnboardingPracticeHost(_ hostProcessID: Int?, now: TimeInterval = CFAbsoluteTimeGetCurrent()) -> Bool {
    self.isMarkedHost(
      hostProcessID, pidKey: SharedKey.onboardingPracticePid,
      timeKey: SharedKey.onboardingPracticeAt, now: now
    )
  }

  func isOnboardingKeyboardTestHost(_ hostProcessID: Int?, now: TimeInterval = CFAbsoluteTimeGetCurrent()) -> Bool {
    self.isMarkedHost(
      hostProcessID, pidKey: SharedKey.onboardingKeyboardTestPid,
      timeKey: SharedKey.onboardingKeyboardTestAt, now: now
    )
  }

  private func isMarkedHost(
    _ hostProcessID: Int?, pidKey: String, timeKey: String, now: TimeInterval
  ) -> Bool {
    let pid = self.defaults.integer(forKey: pidKey)
    let markedAt = self.defaults.double(forKey: timeKey)
    guard pid > 0, markedAt > 0,
          now >= markedAt, now - markedAt < Self.practiceMarkTTL else { return false }
    return hostProcessID.map { $0 == pid } ?? true
  }

  func showsMicHint(hostProcessID: Int?) -> Bool {
    self.isOnboardingPracticeHost(hostProcessID) && !self.isMicHintDismissed
  }

  private static let practiceMarkTTL: TimeInterval = 30 * 60
}
