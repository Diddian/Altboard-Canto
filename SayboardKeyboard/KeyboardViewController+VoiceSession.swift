import UIKit

extension KeyboardViewController {
  func startVoiceSessionActivity() {
    guard self.hasFullAccess, AppGroup.containerURL != nil else { return }
    guard self.voiceSessionActivityTimer == nil else { return }
    self.voiceSessionActivityOwner = UUID()
    self.renewVoiceSessionActivity()
    let timer = Timer(timeInterval: VoiceSessionPolicy.keyboardRenewalInterval, repeats: true) { [weak self] _ in
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        guard self.voiceSessionActivityTimer?.isValid == true,
              self.dictationStartupVisible else { return }
        guard self.viewIfLoaded?.window != nil, Self.activeInstance === self else {
          self.stopVoiceSessionActivity()
          return
        }
        self.renewVoiceSessionActivity()
      }
    }
    self.voiceSessionActivityTimer = timer
    RunLoop.main.add(timer, forMode: .common)
  }

  func stopVoiceSessionActivity() {
    self.voiceSessionActivityTimer?.invalidate()
    self.voiceSessionActivityTimer = nil
    let settings = SharedSettings()
    settings.synchronize()
    guard settings.voiceKeyboardActivity?.canBeEnded(by: self.voiceSessionActivityOwner) == true
    else { return }
    settings.voiceKeyboardActivity = VoiceSessionPolicy.KeyboardActivity(
      owner: self.voiceSessionActivityOwner, updatedAt: Date().timeIntervalSinceReferenceDate,
      visible: false
    )
    settings.synchronize()
    TranscriptionBridge.postDarwinNotification(DarwinNotificationName.keyboardVoiceActivityChanged)
  }

  private func renewVoiceSessionActivity() {
    guard self.hasFullAccess else {
      self.stopVoiceSessionActivity()
      return
    }
    let settings = SharedSettings()
    settings.voiceKeyboardActivity = VoiceSessionPolicy.KeyboardActivity(
      owner: self.voiceSessionActivityOwner, updatedAt: Date().timeIntervalSinceReferenceDate,
      visible: true
    )
    settings.synchronize()
    // Keeping an existing session awake never starts the microphone or ASR.
    TranscriptionBridge.postDarwinNotification(DarwinNotificationName.keyboardVoiceActivityChanged)
    self.keyboardState.syncVoiceSessionReadiness()
  }
}
