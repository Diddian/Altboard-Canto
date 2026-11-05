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
  @State private var keyboardTraceCount = 0
  @State private var featureTraceCount = 0
  @State private var showsDevelopmentTraces = false
  @State private var keyboardTraceExportURL: URL?
  @State private var confirmTraceClear = false
  @State private var traceExportFailed = false
  @AppStorage(SharedKey.keyboardTouchDebugOverlay,
              store: UserDefaults(suiteName: AppGroup.identifier))
  private var showTouchTargets = false

  var body: some View {
    Form {
      self.permissionsSection
      self.modelsSection
      self.audioSection
      self.touchTargetSection
      self.liveDictationSection
      self.testSection
      self.crashSection
      #if !APPSTORE
      self.developmentTraceSection
      #endif
      self.exportSection
    }
    .navigationTitle("Diagnostics")
    .navigationBarTitleDisplayMode(.inline)
    .onAppear(perform: self.refresh)
    .confirmationDialog("Clear development traces?", isPresented: self.$confirmTraceClear) {
      Button("Clear Traces", role: .destructive) {
        FeatureDiagnostics.clearAll()
        self.keyboardTraceCount = 0
        self.featureTraceCount = 0
      }
    }
    .sheet(isPresented: Binding(
      get: { self.keyboardTraceExportURL != nil },
      set: { if !$0 { self.removeKeyboardTraceExport() } }
    ), onDismiss: { self.removeKeyboardTraceExport() }) {
      if let url = self.keyboardTraceExportURL {
        KeyboardTraceShareSheet(url: url)
      }
    }
    .alert("Development diagnostics export failed", isPresented: self.$traceExportFailed) {
      Button("OK", role: .cancel) {}
    }
  }

  private var permissionsSection: some View {
    Section {
      LabeledContent("Microphone (iOS)", value: self.micStatus)
      LabeledContent("Keyboard detected", value: self.yesNo(self.permissions.isKeyboardAdded))
      LabeledContent("Main App Group", value: self.permissions.mainGroupTestResult)
      LabeledContent("App Group ID", value: AppGroup.resolutionDescription)
      LabeledContent("App build", value: self.appBuild)
      LabeledContent("Keyboard build", value: self.keyboardBuild)
      LabeledContent("Keyboard report", value: self.permissions.keyboardProbeSummary)
      LabeledContent("Keyboard Full Access", value: self.report(self.permissions.keyboardReportedFullAccess))
      LabeledContent("Keyboard App Group", value: self.report(self.permissions.keyboardReportedGroupAvailable))
      LabeledContent("Selected keyboard mode", value: SharedSettings().keyboardKind.displayNameKey)
      LabeledContent("Key arrangement", value: SharedSettings().keyboardLetterArrangement.rawValue.uppercased())
      LabeledContent("Keyboard canvas", value: self.fixedKeyboardHeight)
      if SharedSettings().keyboardKind == .standard {
        LabeledContent("Microphone layout", value: SharedSettings().microphoneKeyboardLayout.displayName)
      }
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

  private var touchTargetSection: some View {
    Section {
      Toggle("Show Key Touch Areas", isOn: self.$showTouchTargets)
      Text("In the Alphabet keyboard: orange outlines show the actual contiguous touch cells, teal dashed outlines show the visible keys. Switch off after testing. No typed words or raw touch coordinates are saved.")
        .font(.footnote)
        .foregroundStyle(.secondary)
      LabeledContent("Boundary adjustment limit", value: "12% predictive, 18% combined")
      NavigationLink("Swipe & Touch Counters, Learning and Reset") {
        SwipeTouchDiagnosticsView()
      }
    } header: {
      Text("Keyboard Touch Diagnostics")
    }
  }

  private var liveDictationSection: some View {
    Section("Live Dictation") {
      LabeledContent("Enabled", value:
        self.yesNo(SharedSettings().experimentalLiveDictationEnabled))
      LabeledContent("Recognizer state", value: String(describing: self.speech.activeLoadState))
      LabeledContent("Last live step", value: self.speech.liveDictationStatus)
      Text("If the model cannot load during recording, audio is preserved for the normal final transcription. No spoken text is stored in these counters.")
        .font(.footnote).foregroundStyle(.secondary)
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

  #if !APPSTORE
  private var developmentTraceSection: some View {
    Section {
      DisclosureGroup("Development Traces", isExpanded: self.$showsDevelopmentTraces) {
        LabeledContent("Keyboard lifecycle", value: "\(self.keyboardTraceCount)")
        LabeledContent("Feature milestones", value: "\(self.featureTraceCount)")
        Button("Share Development Diagnostics JSON") {
          if let url = FeatureDiagnostics.exportFileURL() {
            self.keyboardTraceExportURL = url
          } else {
            self.traceExportFailed = true
          }
        }
        Button("Copy Development Diagnostics JSON") {
          UIPasteboard.general.string = FeatureDiagnostics.exportJSON()
        }
        Button("Refresh Diagnostic Counts") {
          self.keyboardTraceCount = KeyboardLifecycleTrace.eventCount
          self.featureTraceCount = FeatureDiagnostics.eventCount
        }
        Button("Clear Development Traces", role: .destructive) {
          self.confirmTraceClear = true
        }
      }
    } footer: {
      Text("Local metadata only. Export after a failure. Nothing uploads automatically.")
    }
  }
  #endif

  private var exportSection: some View {
    Section {
      NavigationLink {
        CantoneseRomanizationDiagnosticsView()
      } label: {
        Label("Cantonese Learning & JSON Export", systemImage: "character.book.closed")
      }
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

  private var appBuild: String {
    String((Bundle.main.infoDictionary?["AltboardBuildSHA"] as? String ?? "unstamped").prefix(12))
  }

  private var keyboardBuild: String {
    String((AppGroup.sharedDefaults?.string(forKey: SharedKey.keyboardBuildSHA) ?? "not reported").prefix(12))
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
    self.keyboardTraceCount = KeyboardLifecycleTrace.eventCount
    self.featureTraceCount = FeatureDiagnostics.eventCount
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

  private var fixedKeyboardHeight: String {
    let settings = SharedSettings()
    let height = KeyboardLayoutGeometry.height(
      kind: settings.keyboardKind,
      microphoneLayout: settings.microphoneKeyboardLayout
    )
    return "\(Int(height)) pt (fixed iPhone layout)"
  }

  private func removeKeyboardTraceExport() {
    guard let url = self.keyboardTraceExportURL else { return }
    self.keyboardTraceExportURL = nil
    try? FileManager.default.removeItem(at: url)
  }

  private var summary: String {
    [
      "Altboard-Canto Diagnostics",
      "Version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")",
      "App build SHA: \(self.appBuild)",
      "Keyboard build SHA: \(self.keyboardBuild)",
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
      "Keyboard canvas: \(self.fixedKeyboardHeight)",
      "Microphone layout: \(SharedSettings().microphoneKeyboardLayout.displayName)",
      "Cantonese enabled: \(SharedSettings().preferredSpokenLanguages.contains("yue"))",
      "Romanization: \(SharedSettings().keyboardRomanizationScheme.displayName)",
      "Offline IME: \(self.offlineImeStatus)",
      "Haptic capable: \(CHHapticEngine.capabilitiesForHardware().supportsHaptics)",
      "Haptic enabled: \(SharedSettings().keyboardHapticsEnabled)",
      "Haptic engine: \(SharedSettings().keyboardHapticDriver.displayName)",
      "Haptic requested count: \(KeyboardHapticTrace.total)",
      "Haptic request trace (no typed characters):",
      KeyboardHapticTrace.events.joined(separator: "\n"),
      "Keyboard lifecycle trace events: \(self.keyboardTraceCount)",
      "Feature diagnostic events: \(self.featureTraceCount)",
      "Keyboard interaction trace (no text):",
      KeyboardInputTrace.events.joined(separator: "\n"),
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

private struct KeyboardTraceShareSheet: UIViewControllerRepresentable {
  let url: URL

  func makeUIViewController(context: Context) -> UIActivityViewController {
    UIActivityViewController(activityItems: [self.url], applicationActivities: nil)
  }

  func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
