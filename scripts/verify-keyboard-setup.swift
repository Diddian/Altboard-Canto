import Foundation

// Isolate the record-store fixture from application preferences.
enum SharedKey {
  static let onboardingRecord = "onboarding-record-test"
}

@main
enum KeyboardSetupSmoke {
  static func main() throws {
    for (response, expected) in [
      ("nei5", ChineseInputMode.phonetic), ("NEI", .phonetic),
      (" OF ", .quick), ("人火", .quick), ("o n f", .cangjie),
      ("人弓火", .cangjie), (",/,n/", .stroke), ("丿丨丿乛丨", .stroke)
    ] {
      precondition(KeyboardSetupPolicy.suggestedMethod(for: response) == expected)
    }
    for response in ["", "ab", "日月", "明", "unknown", String(repeating: "n", count: 33)] {
      precondition(KeyboardSetupPolicy.suggestedMethod(for: response) == nil)
    }
    precondition(KeyboardSetupPolicy.example(for: .quick).contains("OF"))
    precondition(KeyboardSetupPolicy.example(for: .cangjie).contains("ONF"))
    precondition(!KeyboardSetupPolicy.canFinishTypingTest(confirmedKeyboard: false, text: "hello"))
    precondition(!KeyboardSetupPolicy.canFinishTypingTest(confirmedKeyboard: true, text: " \n "))
    precondition(KeyboardSetupPolicy.canFinishTypingTest(confirmedKeyboard: true, text: "你好"))

    precondition(progress(OnboardingRecord()).currentStep == .inputMethod)
    var record = OnboardingRecord()
    record.pass(.inputMethod)
    precondition(progress(record).currentStep == .languages)
    record.postponeVoiceSetup()
    precondition(record.chosenModel == nil)
    precondition(record.postponedSteps.isSuperset(of: [.languages, .microphone]))
    precondition(progress(record).currentStep == .keyboard)
    precondition(progress(record).nextStep(after: .languages) == .keyboard)
    precondition(progress(record).nextStep(after: .keyboard) == nil)
    precondition(progress(record).shownSteps(current: .keyboard) == [.inputMethod, .languages, .keyboard])
    precondition(progress(record, ready: true).nextStep(after: .keyboard) == nil)
    record.pass(.keyboard)
    let decoded = try JSONDecoder().decode(OnboardingRecord.self, from: JSONEncoder().encode(record))
    precondition(decoded == record)
    precondition(progress(decoded, ready: true).currentStep == nil)

    let legacyJSON = #"{"passedSteps":["languages","microphone","keyboard","keyboardType","writingStyle","practice"],"chosenModel":"parakeet-v3"}"#
    let legacy = try JSONDecoder().decode(OnboardingRecord.self, from: Data(legacyJSON.utf8))
    precondition(!legacy.prefersTypingOnly)
    precondition(legacy.chosenModel == "parakeet-v3")
    precondition(progress(legacy).currentStep == nil)

    record.prefersTypingOnly = false
    record.chosenModel = "parakeet-v3"
    record.pass(.languages)
    precondition(progress(record).nextStep(after: .languages) == .microphone)
    precondition(progress(record, ready: true).nextStep(after: .languages) == .keyboard)
    precondition(progress(record, ready: true).nextStep(after: .writingStyle) == .practice)

    let suite = "app.sayboard.keyboard-setup-tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    record.postponeVoiceSetup()
    OnboardingRecordStore(defaults: defaults).save(record)
    precondition(OnboardingRecordStore(defaults: defaults).load() == record)
    OnboardingRecordStore(defaults: defaults).forgetFinishedPostponements(
      SetupChecklist(microphoneGranted: true, keyboardAdded: true,
        fullAccessGranted: true, hasUsableModel: true)
    )
    precondition(OnboardingRecordStore(defaults: defaults).load().prefersTypingOnly)
    print("Keyboard setup: method matching, typing-only route, legacy records and resumption PASS")
  }

  static func progress(_ record: OnboardingRecord, ready: Bool = false) -> OnboardingProgress {
    OnboardingProgress(record: record, microphoneGranted: ready, keyboardReady: ready,
      hasUsableModel: ready, isDictationLocked: false)
  }
}
