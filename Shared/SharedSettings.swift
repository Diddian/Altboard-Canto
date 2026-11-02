import Foundation

struct SharedSettings {

  init() {
    self.init(defaults: AppGroup.sharedDefaults ?? .standard)
  }

  init(defaults: UserDefaults) {
    self.defaults = defaults
  }

  static let keyboardRequestTTL: TimeInterval = 15.0
  static let defaultKeyboardHapticStrength: Double = 0.55

  let defaults: UserDefaults

  var selectedVariant: ModelVariant {
    get {
      guard
        let raw = defaults.string(forKey: SharedKey.selectedVariant),
        let variant = ModelVariant(rawValue: raw)
      else {
        return .whisperSmall
      }
      return variant
    }
    nonmutating set { defaults.set(newValue.rawValue, forKey: SharedKey.selectedVariant) }
  }

  var isRecording: Bool {
    get { self.defaults.bool(forKey: SharedKey.isRecording) }
    nonmutating set { defaults.set(newValue, forKey: SharedKey.isRecording) }
  }

  var lastDictationOutcome: DictationOutcome? {
    get { self.defaults.string(forKey: SharedKey.lastDictationOutcome).flatMap(DictationOutcome.init(rawValue:)) }
    nonmutating set { defaults.set(newValue?.rawValue, forKey: SharedKey.lastDictationOutcome) }
  }

  var keyboardRequestedDictation: Bool {
    get { self.defaults.bool(forKey: SharedKey.keyboardRequestedDictation) }
    nonmutating set { defaults.set(newValue, forKey: SharedKey.keyboardRequestedDictation) }
  }

  var keyboardRequestedDictationAt: TimeInterval {
    get { self.defaults.double(forKey: SharedKey.keyboardRequestedDictationAt) }
    nonmutating set { defaults.set(newValue, forKey: SharedKey.keyboardRequestedDictationAt) }
  }

  var isSessionActive: Bool {
    get { self.defaults.bool(forKey: SharedKey.isSessionActive) }
    nonmutating set { defaults.set(newValue, forKey: SharedKey.isSessionActive) }
  }

  var mainAppHeartbeat: TimeInterval {
    get { self.defaults.double(forKey: SharedKey.mainAppHeartbeat) }
    nonmutating set { defaults.set(newValue, forKey: SharedKey.mainAppHeartbeat) }
  }

  var sessionAutoStopPolicy: SessionAutoStopPolicy {
    get {
      guard
        let raw = defaults.string(forKey: SharedKey.sessionAutoStopPolicy),
        let policy = SessionAutoStopPolicy(rawValue: raw)
      else {
        return .fifteenMinutes
      }
      return policy
    }
    nonmutating set { defaults.set(newValue.rawValue, forKey: SharedKey.sessionAutoStopPolicy) }
  }

  /// Explicit Microphone Only appearance. Old height slider values are
  /// intentionally ignored; no height preference can resize Alphabet.
  var microphoneKeyboardLayout: MicrophoneKeyboardLayout {
    get {
      guard let raw = defaults.string(forKey: SharedKey.microphoneKeyboardLayout),
            let layout = MicrophoneKeyboardLayout(rawValue: raw)
      else { return .defaultLayout }
      return layout
    }
    nonmutating set { defaults.set(newValue.rawValue, forKey: SharedKey.microphoneKeyboardLayout) }
  }

  var keyboardLetterArrangement: LetterKeyArrangement {
    get {
      guard let raw = defaults.string(forKey: SharedKey.keyboardLetterArrangement),
            let value = LetterKeyArrangement(rawValue: raw)
      else { return .qwertz }
      return value
    }
    nonmutating set { defaults.set(newValue.rawValue, forKey: SharedKey.keyboardLetterArrangement) }
  }

  var keyboardKind: KeyboardKind {
    get {
      guard
        let raw = defaults.string(forKey: SharedKey.keyboardKind),
        let kind = KeyboardKind(rawValue: raw)
      else {
        return .standard
      }
      return kind
    }
    nonmutating set { defaults.set(newValue.rawValue, forKey: SharedKey.keyboardKind) }
  }

  var hostBundleId: String? {
    get { self.defaults.string(forKey: SharedKey.hostBundleId) }
    nonmutating set { defaults.set(newValue, forKey: SharedKey.hostBundleId) }
  }

  var canResolveHostApplication: Bool {
    get {
      guard self.defaults.object(forKey: SharedKey.canResolveHostApplication) != nil else {
        return !OperatingSystem.isHostBundleIdBroken
      }
      return self.defaults.bool(forKey: SharedKey.canResolveHostApplication)
    }
    nonmutating set { defaults.set(newValue, forKey: SharedKey.canResolveHostApplication) }
  }

  var retentionPolicy: HistoryRetentionPolicy {
    get {
      guard
        let raw = defaults.string(forKey: SharedKey.retentionPolicy),
        let policy = HistoryRetentionPolicy(rawValue: raw)
      else {
        return .forever
      }
      return policy
    }
    nonmutating set { defaults.set(newValue.rawValue, forKey: SharedKey.retentionPolicy) }
  }

  var downloadInProgressVariants: Set<ModelVariant> {
    get {
      guard let rawValues = defaults.stringArray(forKey: SharedKey.downloadInProgressVariants) else {
        return []
      }
      return Set(rawValues.compactMap { ModelVariant(rawValue: $0) })
    }
    nonmutating set {
      if newValue.isEmpty {
        defaults.removeObject(forKey: SharedKey.downloadInProgressVariants)
      } else {
        defaults.set(newValue.map(\.rawValue), forKey: SharedKey.downloadInProgressVariants)
      }
    }
  }

  var preferredLanguagesPerVariant: [String: [String]] {
    get {
      guard let data = defaults.data(forKey: SharedKey.preferredLanguagesPerVariant) else {
        return [:]
      }
      return (try? JSONDecoder().decode([String: [String]].self, from: data)) ?? [:]
    }
    nonmutating set {
      if newValue.isEmpty {
        defaults.removeObject(forKey: SharedKey.preferredLanguagesPerVariant)
      } else {
        let data = try? JSONEncoder().encode(newValue)
        defaults.set(data, forKey: SharedKey.preferredLanguagesPerVariant)
      }
    }
  }

  /// One user preference shared by onboarding, output toggle and ASR checks.
  /// Missing key is migrated from the previous per-model preference where possible.
  var preferredSpokenLanguages: [String] {
    get {
      if let stored = defaults.stringArray(forKey: SharedKey.preferredSpokenLanguages) {
        return PreferredVoiceLanguages.normalized(stored)
      }
      let legacy = preferredLanguages(for: selectedVariant)
      return legacy.isEmpty
        ? PreferredVoiceLanguages.legacyChoices
        : PreferredVoiceLanguages.normalized(Array(legacy).sorted())
    }
    nonmutating set {
      defaults.set(PreferredVoiceLanguages.normalized(newValue), forKey: SharedKey.preferredSpokenLanguages)
    }
  }

  var hasUsableModel: Bool {
    get { self.defaults.bool(forKey: SharedKey.hasUsableModel) }
    nonmutating set { defaults.set(newValue, forKey: SharedKey.hasUsableModel) }
  }

  var parakeetV3NeedsRedownload: Bool {
    get { self.defaults.bool(forKey: SharedKey.parakeetV3NeedsRedownload) }
    nonmutating set { defaults.set(newValue, forKey: SharedKey.parakeetV3NeedsRedownload) }
  }

  var audioLevel: Float {
    get { self.defaults.float(forKey: SharedKey.audioLevel) }
    nonmutating set { defaults.set(newValue, forKey: SharedKey.audioLevel) }
  }

  var isMicrophoneAuthorized: Bool {
    get { self.defaults.bool(forKey: SharedKey.isMicrophoneAuthorized) }
    nonmutating set { defaults.set(newValue, forKey: SharedKey.isMicrophoneAuthorized) }
  }

  var hasFullAccess: Bool {
    get { self.defaults.bool(forKey: SharedKey.hasFullAccess) }
    nonmutating set { defaults.set(newValue, forKey: SharedKey.hasFullAccess) }
  }

  var isModelLoading: Bool {
    get { self.defaults.bool(forKey: SharedKey.isModelLoading) }
    nonmutating set { defaults.set(newValue, forKey: SharedKey.isModelLoading) }
  }

  var hasPreparedModelOnce: Bool {
    get { self.defaults.bool(forKey: SharedKey.hasPreparedModelOnce) }
    nonmutating set { defaults.set(newValue, forKey: SharedKey.hasPreparedModelOnce) }
  }

  var useCustomSpaceBar: Bool {
    get { self.defaults.bool(forKey: SharedKey.useCustomSpaceBar) }
    nonmutating set { defaults.set(newValue, forKey: SharedKey.useCustomSpaceBar) }
  }

  /// App Core Haptics intensity; Apple's native keyboard strength is not exposed.
  var keyboardHapticStrength: Double {
    get {
      let saved = defaults.object(forKey: SharedKey.keyboardHapticStrength) as? Double ?? Self.defaultKeyboardHapticStrength
      return min(1.0, max(0.15, saved))
    }
    nonmutating set {
      defaults.set(min(1.0, max(0.15, newValue)), forKey: SharedKey.keyboardHapticStrength)
    }
  }

  // Read the actual App Group domain, not UserDefaults.standard's registration.
  // The initial (unset) value is ON; an explicit user choice of false wins.
  var keyboardHapticsEnabled: Bool {
    get { defaults.object(forKey: SharedKey.keyboardHapticsEnabled) as? Bool ?? true }
    nonmutating set { defaults.set(newValue, forKey: SharedKey.keyboardHapticsEnabled) }
  }

  var keyboardHapticDriver: KeyboardHapticDriver {
    get {
      guard let saved = defaults.string(forKey: SharedKey.keyboardHapticDriver) else {
        return .coreHaptics
      }
      return KeyboardHapticDriver(rawValue: saved) ?? .coreHaptics
    }
    nonmutating set {
      defaults.set(newValue.rawValue, forKey: SharedKey.keyboardHapticDriver)
    }
  }

  var keyboardAutoCapitalizationEnabled: Bool {
    get { defaults.object(forKey: SharedKey.keyboardAutoCapitalizationEnabled) as? Bool ?? true }
    nonmutating set { defaults.set(newValue, forKey: SharedKey.keyboardAutoCapitalizationEnabled) }
  }

  var keyboardRomanizationScheme: CantoneseRomanizationScheme {
    get {
      guard let value = defaults.string(forKey: SharedKey.keyboardRomanizationScheme) else { return .jyutping }
      return CantoneseRomanizationScheme(rawValue: value) ?? .jyutping
    }
    nonmutating set { defaults.set(newValue.rawValue, forKey: SharedKey.keyboardRomanizationScheme) }
  }

  var periodShortcutEnabled: Bool {
    get { defaults.object(forKey: SharedKey.periodShortcutEnabled) as? Bool ?? true }
    nonmutating set { defaults.set(newValue, forKey: SharedKey.periodShortcutEnabled) }
  }

  var alsoCopyToClipboard: Bool {
    get { self.defaults.bool(forKey: SharedKey.alsoCopyToClipboard) }
    nonmutating set { defaults.set(newValue, forKey: SharedKey.alsoCopyToClipboard) }
  }

  var needsInputModeSwitchKey: Bool {
    get { defaults.object(forKey: SharedKey.needsInputModeSwitchKey) as? Bool ?? true }
    nonmutating set { defaults.set(newValue, forKey: SharedKey.needsInputModeSwitchKey) }
  }

  var isTranslationMode: Bool {
    get { self.defaults.bool(forKey: SharedKey.isTranslationMode) }
    nonmutating set { defaults.set(newValue, forKey: SharedKey.isTranslationMode) }
  }

  var voiceCleanupEnabled: Bool {
    get { defaults.object(forKey: SharedKey.voiceCleanupEnabled) as? Bool ?? false }
    nonmutating set { defaults.set(newValue, forKey: SharedKey.voiceCleanupEnabled) }
  }

  /// Whether the latest dictation result has already used the main-app text model.
  var lastVoiceOutputProcessed: Bool {
    get { defaults.bool(forKey: SharedKey.lastVoiceOutputProcessed) }
    nonmutating set { defaults.set(newValue, forKey: SharedKey.lastVoiceOutputProcessed) }
  }

  var voiceOutputTarget: VoiceOutputTarget {
    get {
      guard let raw = defaults.string(forKey: SharedKey.voiceOutputTarget) else { return .original }
      return VoiceOutputTarget(rawValue: raw) ?? .original
    }
    nonmutating set { defaults.set(newValue.rawValue, forKey: SharedKey.voiceOutputTarget) }
  }

  var voiceOutputRegister: VoiceOutputRegister {
    get {
      guard let raw = defaults.string(forKey: SharedKey.voiceOutputRegister) else { return .faithful }
      return VoiceOutputRegister(rawValue: raw) ?? .faithful
    }
    nonmutating set { defaults.set(newValue.rawValue, forKey: SharedKey.voiceOutputRegister) }
  }

  var voiceCustomLanguage: String {
    get { defaults.string(forKey: SharedKey.voiceCustomLanguage) ?? "" }
    nonmutating set { defaults.set(newValue, forKey: SharedKey.voiceCustomLanguage) }
  }

  var voiceOutputConfiguration: VoiceOutputConfiguration {
    VoiceOutputConfiguration(
      cleanupEnabled: self.voiceCleanupEnabled,
      target: self.voiceOutputTarget,
      register: self.voiceOutputRegister,
      customLanguage: self.voiceCustomLanguage
    )
  }

  var defaultWritingStyle: WritingStyle {
    get {
      guard
        let raw = defaults.string(forKey: SharedKey.defaultWritingStyle),
        let style = WritingStyle(stored: raw)
      else {
        return .formal
      }
      return style
    }
    nonmutating set { defaults.set(newValue.rawValue, forKey: SharedKey.defaultWritingStyle) }
  }

  var downloadStartedAt: Date? {
    get {
      let interval = self.defaults.double(forKey: SharedKey.downloadStartedAt)
      return interval > 0 ? Date(timeIntervalSince1970: interval) : nil
    }
    nonmutating set {
      if let newValue {
        defaults.set(newValue.timeIntervalSince1970, forKey: SharedKey.downloadStartedAt)
      } else {
        defaults.removeObject(forKey: SharedKey.downloadStartedAt)
      }
    }
  }

  var selectedLLMVariant: LLMModelVariant {
    get {
      guard
        let raw = defaults.string(forKey: SharedKey.selectedLLMVariant),
        let variant = LLMModelVariant(rawValue: raw)
      else {
        return .qwen35Small
      }
      return variant
    }
    nonmutating set { defaults.set(newValue.rawValue, forKey: SharedKey.selectedLLMVariant) }
  }

  var completedLLMUpgradeFrom: LLMModelVariant? {
    get {
      guard let raw = defaults.string(forKey: SharedKey.completedLLMUpgradeFrom) else { return nil }
      return LLMModelVariant(rawValue: raw)
    }
    nonmutating set {
      if let newValue {
        defaults.set(newValue.rawValue, forKey: SharedKey.completedLLMUpgradeFrom)
      } else {
        defaults.removeObject(forKey: SharedKey.completedLLMUpgradeFrom)
      }
    }
  }

  var llmDownloadInProgressVariants: Set<LLMModelVariant> {
    get {
      guard let rawValues = defaults.stringArray(forKey: SharedKey.llmDownloadInProgressVariants) else {
        return []
      }
      return Set(rawValues.compactMap { LLMModelVariant(rawValue: $0) })
    }
    nonmutating set {
      if newValue.isEmpty {
        defaults.removeObject(forKey: SharedKey.llmDownloadInProgressVariants)
      } else {
        defaults.set(newValue.map(\.rawValue), forKey: SharedKey.llmDownloadInProgressVariants)
      }
    }
  }

  var declinedLLMUpgrades: Set<LLMModelVariant> {
    get {
      guard let rawValues = defaults.stringArray(forKey: SharedKey.declinedLLMUpgrades) else {
        return []
      }
      return Set(rawValues.compactMap { LLMModelVariant(rawValue: $0) })
    }
    nonmutating set {
      if newValue.isEmpty {
        defaults.removeObject(forKey: SharedKey.declinedLLMUpgrades)
      } else {
        defaults.set(newValue.map(\.rawValue), forKey: SharedKey.declinedLLMUpgrades)
      }
    }
  }

  var hasUsableLLMModel: Bool {
    get { self.defaults.bool(forKey: SharedKey.hasUsableLLMModel) }
    nonmutating set { defaults.set(newValue, forKey: SharedKey.hasUsableLLMModel) }
  }

  var isLLMProcessing: Bool {
    get { self.defaults.bool(forKey: SharedKey.isLLMProcessing) }
    nonmutating set { defaults.set(newValue, forKey: SharedKey.isLLMProcessing) }
  }

  var llmEnabled: Bool {
    get { self.defaults.bool(forKey: SharedKey.llmEnabled) }
    nonmutating set { defaults.set(newValue, forKey: SharedKey.llmEnabled) }
  }

  var defaultLLMActionSelection: LLMActionSelection {
    get {
      if let data = defaults.data(forKey: SharedKey.defaultLLMActionSelection) {
        if let selection = try? JSONDecoder().decode(LLMActionSelection.self, from: data) {
          return selection
        }
      }
      if
        let raw = defaults.string(forKey: SharedKey.defaultLLMAction),
        let action = LLMAction(rawValue: raw)
      {
        let migrated = LLMActionSelection.preset(action)
        let data = try? JSONEncoder().encode(migrated)
        self.defaults.set(data, forKey: SharedKey.defaultLLMActionSelection)
        self.defaults.removeObject(forKey: SharedKey.defaultLLMAction)
        return migrated
      }
      return .none
    }
    nonmutating set {
      let data = try? JSONEncoder().encode(newValue)
      defaults.set(data, forKey: SharedKey.defaultLLMActionSelection)
      defaults.removeObject(forKey: SharedKey.defaultLLMAction)
    }
  }

  var llmCustomPrompts: [LLMCustomPrompt] {
    get {
      guard let data = defaults.data(forKey: SharedKey.llmCustomPrompts) else { return [] }
      return (try? JSONDecoder().decode([LLMCustomPrompt].self, from: data)) ?? []
    }
    nonmutating set {
      let data = try? JSONEncoder().encode(newValue)
      defaults.set(data, forKey: SharedKey.llmCustomPrompts)
    }
  }

  var longPressLLMAction: LLMActionSelection {
    get {
      guard let data = defaults.data(forKey: SharedKey.longPressLLMAction) else { return .none }
      return (try? JSONDecoder().decode(LLMActionSelection.self, from: data)) ?? .none
    }
    nonmutating set {
      let data = try? JSONEncoder().encode(newValue)
      defaults.set(data, forKey: SharedKey.longPressLLMAction)
    }
  }

  var disabledLLMActions: Set<LLMAction> {
    get {
      guard let rawValues = defaults.stringArray(forKey: SharedKey.disabledLLMActions) else {
        return []
      }
      return Set(rawValues.compactMap { LLMAction(rawValue: $0) })
    }
    nonmutating set {
      if newValue.isEmpty {
        defaults.removeObject(forKey: SharedKey.disabledLLMActions)
      } else {
        defaults.set(newValue.map(\.rawValue), forKey: SharedKey.disabledLLMActions)
      }
    }
  }

  var dictationSessionToken: String? {
    get { self.defaults.string(forKey: SharedKey.dictationSessionToken) }
    nonmutating set { defaults.set(newValue, forKey: SharedKey.dictationSessionToken) }
  }

  var cantoneseCorrectionRules: [CantoneseCorrectionRule] {
    get {
      guard let data = defaults.data(forKey: SharedKey.cantoneseCorrectionRules) else { return [] }
      return (try? JSONDecoder().decode([CantoneseCorrectionRule].self, from: data)) ?? []
    }
    nonmutating set {
      let encoded = try? JSONEncoder().encode(Array(newValue.prefix(50)))
      defaults.set(encoded, forKey: SharedKey.cantoneseCorrectionRules)
    }
  }

  var snippets: [Snippet] {
    get {
      guard let data = defaults.data(forKey: SharedKey.snippets) else {
        return []
      }
      return (try? JSONDecoder().decode([Snippet].self, from: data)) ?? []
    }
    nonmutating set {
      let data = try? JSONEncoder().encode(newValue)
      defaults.set(data, forKey: SharedKey.snippets)
    }
  }

  func isKeyboardRequestRecent(now: TimeInterval = CFAbsoluteTimeGetCurrent()) -> Bool {
    self.defaults.synchronize()
    let timestamp = self.keyboardRequestedDictationAt
    guard self.keyboardRequestedDictation, timestamp > 0 else { return false }
    return (now - timestamp) <= Self.keyboardRequestTTL
  }

  @discardableResult
  func consumeKeyboardRequestIfRecent(now: TimeInterval = CFAbsoluteTimeGetCurrent()) -> Bool {
    guard self.isKeyboardRequestRecent(now: now) else { return false }
    self.keyboardRequestedDictation = false
    self.keyboardRequestedDictationAt = 0
    self.defaults.synchronize()
    return true
  }

  func preferredLanguages(for variant: ModelVariant) -> Set<String> {
    Set(self.preferredLanguagesPerVariant[variant.rawValue] ?? [])
  }

  func setPreferredLanguages(_ languages: Set<String>, for variant: ModelVariant) {
    var dict = self.preferredLanguagesPerVariant
    if languages.isEmpty {
      dict.removeValue(forKey: variant.rawValue)
    } else {
      dict[variant.rawValue] = languages.sorted()
    }
    self.preferredLanguagesPerVariant = dict
  }

  func synchronize() {
    self.defaults.synchronize()
  }

}
