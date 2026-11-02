import SwiftUI
import UIKit
import CoreHaptics

/// Persistent Settings destination; independent of initial setup/onboarding.
struct DiagnosticsView: View {
  @EnvironmentObject private var permissions: PermissionService
  @EnvironmentObject private var speech: SpeechRecognitionService
  @EnvironmentObject private var models: ModelDownloadService
  @EnvironmentObject private var llmModels: LLMDownloadService

  @State private var testResult = ""
  @State private var rawASRResult = ""
  @State private var breadcrumbs = [String]()
  @State private var hapticEvents = [String]()
  @State private var hapticTotal = 0
  @State private var coreHapticStatus = ""
  @State private var coreHapticEngine: CHHapticEngine?
  @StateObject private var sensoryPulse = KeyboardSensoryPulse.shared

  var body: some View {
    Form {
      self.permissionsSection
      self.modelsSection
      self.audioSection
      self.hapticsSection
      self.testSection
      self.crashSection
      self.exportSection
    }
    .navigationTitle("Diagnostics")
    .navigationBarTitleDisplayMode(.inline)
    .onAppear(perform: self.refresh)
    .sensoryFeedback(.selection, trigger: self.sensoryPulse.count)
  }

  private var permissionsSection: some View {
    Section {
      LabeledContent("Microphone (iOS)", value: self.micStatus)
      LabeledContent("Keyboard detected", value: self.yesNo(self.permissions.isKeyboardAdded))
      LabeledContent("Main App Group", value: self.permissions.mainGroupTestResult)
      LabeledContent("App Group ID", value: AppGroup.resolutionDescription)
      LabeledContent("Keyboard report", value: self.permissions.keyboardProbeSummary)
      LabeledContent("Keyboard Full Access", value: self.report(self.permissions.keyboardReportedFullAccess))
      LabeledContent("Keyboard App Group", value: self.report(self.permissions.keyboardReportedGroupAvailable))
      LabeledContent("Selected keyboard mode", value: SharedSettings().keyboardKind.displayNameKey)
      LabeledContent("Key arrangement", value: SharedSettings().keyboardLetterArrangement.rawValue.uppercased())
      LabeledContent("Keyboard height", value: String(Int(SharedSettings().keyboardHeightScale * 100)) + "%")
      LabeledContent("Cantonese in preferred languages", value:
        self.yesNo(SharedSettings().preferredSpokenLanguages.contains("yue")))
      LabeledContent("Cantonese romanization", value: SharedSettings().keyboardRomanizationScheme.displayName)
      LabeledContent("IME initialization",
        value: self.offlineImeStatus)
    } header: {
      Text("Permissions and Signing")
    }
  }

  private var modelsSection: some View {
    Section {
      LabeledContent("Speech model", value: self.models.selectedVariant.displayName)
      LabeledContent("Speech files present", value: self.yesNo(self.models.isDownloaded(self.models.selectedVariant)))
      LabeledContent("Speech engine", value: String(describing: self.models.selectedVariant.engine))
      LabeledContent("Recognizer state", value: String(describing: self.speech.activeLoadState))
      LabeledContent("Text LLM", value: self.llmModels.selectedVariant.displayName)
      LabeledContent("Text LLM installed", value: self.yesNo(self.llmModels.hasUsableModel))
    } header: {
      Text("Offline Models")
    }
  }

  private var audioSection: some View {
    Section {
      LabeledContent("Audio session", value: self.speech.session.isSessionActive ? "Active" : "Inactive")
      LabeledContent("Audio engine", value: self.speech.session.audioEngine.isRunning ? "Running" : "Stopped")
      LabeledContent("Recording", value: self.yesNo(self.speech.isRecording))
      LabeledContent("Available storage", value: self.availableStorage)
      LabeledContent("App bundle ID", value: Bundle.main.bundleIdentifier ?? "Unknown")
      LabeledContent("iOS", value: UIDevice.current.systemVersion)
    } header: {
      Text("Audio and Device")
    }
  }

  private var hapticsSection: some View {
    Section {
      LabeledContent("Hardware haptics", value: self.yesNo(CHHapticEngine.capabilitiesForHardware().supportsHaptics))
      LabeledContent("App Group haptics enabled", value: self.yesNo(SharedSettings().keyboardHapticsEnabled))
      LabeledContent("Requested events", value: String(self.hapticTotal))
      LabeledContent("Keyboard Full Access", value: self.report(self.permissions.keyboardReportedFullAccess))
      LabeledContent("Configured haptic engine", value: SharedSettings().keyboardHapticDriver.displayName)
      ForEach(KeyboardHaptics.Technique.allCases, id: \.rawValue) { technique in
        Button("Test " + technique.displayName + " haptic") {
          KeyboardHaptics.key(enabled: true, technique: technique)
          self.refreshHaptics()
        }
      }
      Button("Test Core Haptics (app)") {
        self.testCoreHaptics()
      }
      .disabled(!CHHapticEngine.capabilitiesForHardware().supportsHaptics)
      if !self.coreHapticStatus.isEmpty {
        Text(self.coreHapticStatus)
          .font(.footnote)
          .foregroundStyle(.secondary)
          .textSelection(.enabled)
      }
      if !self.hapticEvents.isEmpty {
        Text(self.hapticEvents.suffix(20).joined(separator: "\n"))
          .font(.system(.caption2, design: .monospaced))
          .textSelection(.enabled)
      }
      Button("Clear haptic trace") {
        KeyboardHapticTrace.clear()
        self.refreshHaptics()
      }
      Button("Refresh haptic trace", action: self.refreshHaptics)
    } header: {
      Text("Haptic Diagnostics")
    } footer: {
      Text("Events record calls, not confirmed physical vibration. Core Haptics errors are recorded separately. App and keyboard extension use separate processes; compare both in this trace.")
    }
  }

  private var testSection: some View {
    Section {
      Button("Refresh all diagnostics", action: self.refresh)
      Button("Test microphone without saving audio") {
        self.permissions.testAudioInput(session: self.speech.session)
        self.refreshBreadcrumbs()
      }
      .disabled(self.speech.isRecording || self.speech.isStopping)
      Text(self.permissions.audioInputTestResult)
        .font(.footnote).foregroundStyle(.secondary)

      Button(self.speech.isRecording ? "Stop and transcribe" : "Test ASR and AI cleanup") {
        self.runDictationTest()
      }
      .disabled(self.speech.isStopping
        || (!self.speech.isRecording
          && (!self.models.hasUsableModel || self.permissions.microphoneState != .granted)))
      if !self.rawASRResult.isEmpty {
        VStack(alignment: .leading, spacing: 4) {
          Text("Raw ASR (before AI cleanup)").font(.caption.weight(.semibold))
          Text(self.rawASRResult).font(.footnote).textSelection(.enabled)
        }
      }
      if !self.testResult.isEmpty {
        VStack(alignment: .leading, spacing: 4) {
          Text("Final output (after cleanup)").font(.caption.weight(.semibold))
          Text(self.testResult).font(.footnote).textSelection(.enabled)
        }
      }
    } header: {
      Text("Functional Tests")
    } footer: {
      Text("Tests run inside Altboard, without the keyboard. Start recording, speak, then tap Stop. If an on-device text LLM is installed, the normal cleanup pipeline runs too.")
    }
  }

  private var crashSection: some View {
    Section {
      Text(self.breadcrumbs.last ?? "No recorded steps")
        .font(.footnote.weight(.semibold))
        .textSelection(.enabled)
      if !self.breadcrumbs.isEmpty {
        Text(self.breadcrumbs.suffix(15).joined(separator: "\n"))
          .font(.system(.caption2, design: .monospaced))
          .foregroundStyle(.secondary)
          .textSelection(.enabled)
      }
      Button("Refresh last execution steps", action: self.refreshBreadcrumbs)
    } header: {
      Text("Last Execution Steps")
    } footer: {
      Text("These steps survive an app crash and contain no spoken text. The last step suggests where the app stopped; it does not prove the reason for termination.")
    }
  }

  private var exportSection: some View {
    Section {
      Button("Copy complete diagnostics") {
        UIPasteboard.general.string = self.summary
      }
    } header: {
      Text("Export")
    } footer: {
      Text("For an iOS crash report: Settings → Privacy & Security → Analytics & Improvements → Analytics Data. Look for an Altboard or Sayboard crash near the failure time.")
    }
  }

  private var micStatus: String {
    switch self.permissions.microphoneState {
    case .granted: "Granted"
    case .denied: "Denied"
    case .undetermined: "Not requested"
    }
  }

  private var offlineImeStatus: String {
    guard let stored = AppGroup.sharedDefaults?.object(forKey: "canto.ime.offlineDictionaryReady") as? Bool else {
      return "Not tested in keyboard"
    }
    return stored ? "Offline dictionary ready" : "Unavailable in keyboard"
  }

  private var availableStorage: String {
    guard let bytes = ModelDiskReserve.availableBytes() else { return "Unknown" }
    return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
  }

  private func report(_ value: Bool?) -> String {
    guard let value else { return "No keyboard report" }
    return value ? "Yes" : "No"
  }

  private func yesNo(_ value: Bool) -> String { value ? "Yes" : "No" }

  private func refresh() {
    self.permissions.refreshAll()
    self.models.verifyExistingModels()
    self.refreshBreadcrumbs()
    self.refreshHaptics()
  }

  private func testCoreHaptics() {
    guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
      self.coreHapticStatus = "This device has no Core Haptics hardware."
      return
    }
    do {
      let engine = try CHHapticEngine()
      self.coreHapticEngine = engine
      try engine.start()
      let event = CHHapticEvent(
        eventType: .hapticTransient,
        parameters: [
          CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.85),
          CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.55)
        ],
        relativeTime: 0
      )
      let pattern = try CHHapticPattern(events: [event], parameters: [])
      let player = try engine.makePlayer(with: pattern)
      try player.start(atTime: 0)
      self.coreHapticStatus = "Core Haptics started; physically felt vibration still requires confirmation."
    } catch {
      self.coreHapticStatus = "Core Haptics error: \(error.localizedDescription)"
    }
  }

  private func refreshHaptics() {
    self.hapticEvents = KeyboardHapticTrace.events
    self.hapticTotal = KeyboardHapticTrace.total
  }

  private func refreshBreadcrumbs() {
    self.breadcrumbs = DictationBreadcrumb.entries
  }

  private func runDictationTest() {
    if self.speech.isRecording {
      self.testResult = "Transcribing and cleaning up..."
      Task {
        await self.speech.stopRecording()
        self.rawASRResult = self.speech.currentRawTranscription
        self.testResult = self.speech.currentTranscription.isEmpty
          ? "No text produced. Check the last execution steps."
          : self.speech.currentTranscription
        self.refreshBreadcrumbs()
      }
      return
    }

    self.permissions.refreshMicrophoneState()
    self.rawASRResult = ""
    self.testResult = "Preparing speech model..."
    Task {
      await self.speech.startRecordingAfterModelLoad()
      self.testResult = self.speech.isRecording
        ? "Recording. Speak and tap Stop and transcribe."
        : "Recording failed to start. Inspect the execution steps below."
      self.refreshBreadcrumbs()
    }
  }

  private var summary: String {
    [
      "Altboard-Canto Diagnostics",
      "Version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")",
      "App: \(Bundle.main.bundleIdentifier ?? "unknown")",
      "iOS: \(UIDevice.current.systemVersion)",
      "Microphone: \(self.micStatus)",
      "Keyboard installed: \(self.permissions.isKeyboardAdded)",
      "Main App Group: \(self.permissions.mainGroupTestResult)",
      "Group ID: \(AppGroup.resolutionDescription)",
      "Keyboard report: \(self.permissions.keyboardProbeSummary)",
      "Keyboard Full Access: \(self.report(self.permissions.keyboardReportedFullAccess))",
      "Keyboard App Group: \(self.report(self.permissions.keyboardReportedGroupAvailable))",
      "Keyboard mode: \(SharedSettings().keyboardKind.displayNameKey)",
      "Keyboard order: \(SharedSettings().keyboardLetterArrangement.rawValue)",
      "Keyboard height: \(SharedSettings().keyboardHeightScale)",
      "Cantonese enabled: \(SharedSettings().preferredSpokenLanguages.contains("yue"))",
      "Romanization: \(SharedSettings().keyboardRomanizationScheme.displayName)",
      "Offline IME: \(self.offlineImeStatus)",
      "Haptic capable: \(CHHapticEngine.capabilitiesForHardware().supportsHaptics)",
      "Haptic enabled: \(SharedSettings().keyboardHapticsEnabled)",
      "Haptic engine: \(SharedSettings().keyboardHapticDriver.displayName)",
      "Haptic requested count: \(KeyboardHapticTrace.total)",
      "Haptic request trace (no typed characters):",
      KeyboardHapticTrace.events.joined(separator: "\n"),
      "Audio engine: \(self.speech.session.audioEngine.isRunning)",
      "Audio test: \(self.permissions.audioInputTestResult)",
      "Speech model: \(self.models.selectedVariant.displayName)",
      "Model downloaded: \(self.models.isDownloaded(self.models.selectedVariant))",
      "Recognizer state: \(String(describing: self.speech.activeLoadState))",
      "LLM installed: \(self.llmModels.hasUsableModel)",
      "Free storage: \(self.availableStorage)",
      "Last execution steps:",
      self.breadcrumbs.joined(separator: "\n"),
    ].joined(separator: "\n")
  }
}
