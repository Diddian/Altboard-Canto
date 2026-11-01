import SwiftUI

struct SetupView: View {

  var body: some View {
    Form {
      Section {
        self.tutorialRow(
          "Allow Microphone Access",
          systemImage: self.checklist.microphoneGranted ? "mic" : "mic.slash",
          isDone: self.checklist.microphoneGranted,
          video: .microphone,
        )
        self.tutorialRow(
          "Add Altboard Keyboard",
          systemImage: "keyboard",
          isDone: self.checklist.keyboardAdded,
          video: .addKeyboard,
        )
        self.tutorialRow(
          "Allow Full Access for Keyboard",
          systemImage: "lock.open",
          isDone: self.checklist.fullAccessGranted,
          video: .fullAccess,
        )
        self.modelRow
      } footer: {
        if !self.checklist.isComplete {
          Text("Altboard won’t work until these settings are configured")
        }
      }
      Section("Sideloading diagnostics") {
        Button("Recheck microphone and keyboard") { self.permissionService.refreshAll() }
        LabeledContent("iOS microphone", value: self.microphoneStatus)
        LabeledContent("Keyboard enabled", value: self.permissionService.isKeyboardAdded ? "Detected" : "Not confirmed")
        LabeledContent("Main App Group", value: self.permissionService.mainGroupTestResult)
        LabeledContent("Keyboard extension", value: self.permissionService.keyboardProbeSummary)
        LabeledContent("Keyboard Full Access (actual)", value: self.boolStatus(self.permissionService.keyboardReportedFullAccess))
        LabeledContent("Keyboard App Group", value: self.boolStatus(self.permissionService.keyboardReportedGroupAvailable))

        if AppGroup.containerURL == nil {
          Label(
            "The signed app cannot open its shared App Group. The keyboard cannot receive microphone status or return recognized text.",
            systemImage: "exclamationmark.triangle"
          )
          .font(.footnote).foregroundStyle(.orange)
        } else if self.permissionService.keyboardProbeTimestamp == 0 {
          Text("Open Altboard keyboard in Notes, return here, then tap Recheck. No keyboard report suggests a sharing or signing issue.")
            .font(.footnote).foregroundStyle(.secondary)
        }

      }

      Section("Functional tests") {
        if self.permissionService.microphoneState != .granted {
          Button("Request or repair microphone access") {
            if self.permissionService.microphoneState == .undetermined {
              self.permissionService.requestMicrophonePermission()
            } else if let url = URL(string: UIApplication.openSettingsURLString) {
              UIApplication.shared.open(url)
            }
          }
        }

        Button("Test main-app microphone (no audio saved)") {
          self.permissionService.testAudioInput(session: self.speechService.session)
        }
        .disabled(self.speechService.isRecording || self.speechService.isStopping)
        Text(self.permissionService.audioInputTestResult)
          .font(.footnote).foregroundStyle(.secondary)

        Button(self.speechService.isRecording ? "Stop test and transcribe" : "Test ASR and AI cleanup in app") {
          self.runDictationTest()
        }
        .disabled(
          self.speechService.isStopping
          || (!self.speechService.isRecording
            && (!self.downloadService.hasUsableModel || self.permissionService.microphoneState != .granted))
        )
        if !self.dictationTestResult.isEmpty {
          Text(self.dictationTestResult)
            .font(.footnote).textSelection(.enabled)
        }

        Button("Copy diagnostic summary") {
          UIPasteboard.general.string = self.diagnosticSummary
        }
      } footer: {
        Text("The microphone and ASR tests run inside the main app. They bypass keyboard communication so you can isolate the failure.")
      }
    }
    .navigationTitle("Setup")
    .navigationBarTitleDisplayMode(.inline)
    .navigationDestination(isPresented: self.$showsModels) {
      ModelsView()
    }
    .onAppear { self.permissionService.refreshAll() }
  }

  private var microphoneStatus: String {
    switch self.permissionService.microphoneState {
    case .granted: "Granted"
    case .denied: "Denied"
    case .undetermined: "Not requested"
    }
  }

  private func boolStatus(_ value: Bool?) -> String {
    guard let value else { return "No keyboard report" }
    return value ? "Yes" : "No"
  }

  private func runDictationTest() {
    if self.speechService.isRecording {
      Task {
        await self.speechService.stopRecording()
        let text = self.speechService.currentTranscription
        self.dictationTestResult = text.isEmpty
          ? "No recognized text. Check microphone input and speech model."
          : text
      }
      return
    }
    self.permissionService.refreshMicrophoneState()
    self.dictationTestResult = "Starting recording..."
    Task {
      await self.speechService.startRecordingAfterModelLoad()
      self.dictationTestResult = self.speechService.isRecording
        ? "Recording: speak, then tap Stop test and transcribe."
        : "Recording could not start. Check microphone and model."
    }
  }

  private var diagnosticSummary: String {
    [
      "Altboard-Canto device diagnostic",
      "App bundle: \(Bundle.main.bundleIdentifier ?? "unknown")",
      "iOS mic: \(self.microphoneStatus)",
      "Keyboard detected: \(self.permissionService.isKeyboardAdded)",
      "Main App Group: \(self.permissionService.mainGroupTestResult)",
      "Keyboard report: \(self.permissionService.keyboardProbeSummary)",
      "Keyboard Full Access: \(self.boolStatus(self.permissionService.keyboardReportedFullAccess))",
      "Keyboard shared group: \(self.boolStatus(self.permissionService.keyboardReportedGroupAvailable))",
      "Audio engine: \(self.permissionService.audioInputTestResult)",
      "Transcription: \(self.speechService.currentTranscription.isEmpty ? "None yet" : "Produced")",
    ].joined(separator: "\n")
  }

  private static let defaultLanguage = AppLanguageConfig.fallback

  @AppStorage(SharedKey.appLanguage) private var selectedAppLanguage = defaultLanguage
  @AppStorage(SharedKey.hasUsableModel, store: AppGroup.sharedDefaults ?? .standard)
  private var hasUsableModel = false
  @AppStorage(SharedKey.parakeetV3NeedsRedownload, store: AppGroup.sharedDefaults ?? .standard)
  private var parakeetV3NeedsRedownload = false
  @SceneStorage(ModelTab.storageKey) private var modelsTab = ModelTab.speechRecognition
  @EnvironmentObject private var speechService: SpeechRecognitionService
  @EnvironmentObject private var downloadService: ModelDownloadService
  @EnvironmentObject private var permissionService: PermissionService
  @EnvironmentObject private var pipTutorialService: PiPTutorialService
  @State private var showsModels = false
  @State private var dictationTestResult = ""

  private var checklist: SetupChecklist {
    SetupChecklist(permissions: self.permissionService, hasUsableModel: self.hasUsableModel)
  }

  @ViewBuilder
  private var modelRow: some View {
    if self.hasUsableModel {
      SetupDoneRow(title: "Download Speech Model", systemImage: "arrow.down.circle")
    } else {
      let title: LocalizedStringKey = self.parakeetV3NeedsRedownload ? "Model Update Required" : "Download Speech Model"
      Button {
        self.modelsTab = .speechRecognition
        self.showsModels = true
      } label: {
        Label(title, systemImage: "arrow.down.circle")
      }
    }
  }

  @ViewBuilder
  private func tutorialRow(
    _ title: LocalizedStringKey,
    systemImage: String,
    isDone: Bool,
    video: TutorialVideo,
  ) -> some View {
    if isDone {
      SetupDoneRow(title: title, systemImage: systemImage)
    } else {
      Button {
        self.pipTutorialService.playTutorial(video, language: self.selectedAppLanguage, thenOpenSettings: true)
      } label: {
        Label(title, systemImage: systemImage)
      }
    }
  }
}

struct SetupCompletedMark: View {
  var body: some View {
    Image(systemName: "checkmark")
      .fontWeight(.semibold)
      .foregroundStyle(.green)
      .accessibilityLabel(Text("Completed"))
  }
}

private struct SetupDoneRow: View {
  let title: LocalizedStringKey
  let systemImage: String

  var body: some View {
    HStack {
      Label(self.title, systemImage: self.systemImage)
      Spacer()
      SetupCompletedMark()
    }
    .accessibilityElement(children: .combine)
  }
}

extension SetupChecklist {
  @MainActor
  init(permissions: PermissionService, hasUsableModel: Bool) {
    self.init(
      microphoneGranted: permissions.microphoneState == .granted,
      keyboardAdded: permissions.isKeyboardAdded,
      fullAccessGranted: permissions.hasFullAccess,
      hasUsableModel: hasUsableModel,
    )
  }
}
