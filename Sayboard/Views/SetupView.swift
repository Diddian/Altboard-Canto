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
        Button("Recheck microphone and keyboard") {
          self.permissionService.refreshAll()
        }
        if self.permissionService.microphoneState != .granted {
          Button("Request or repair microphone access") {
            if self.permissionService.microphoneState == .undetermined {
              self.permissionService.requestMicrophonePermission()
            } else if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
              UIApplication.shared.open(settingsURL)
            }
          }
        }
        Text("iOS microphone permission: \(self.permissionService.microphoneState == .granted ? "Granted" : self.permissionService.microphoneState == .denied ? "Denied" : "Not requested")")
          .font(.footnote)
        Text("Detected keyboard: \(self.permissionService.isKeyboardAdded ? "Yes" : "Not confirmed")")
          .font(.footnote)
        if AppGroup.containerURL == nil {
          Label("Shared App Group storage is unavailable. SideStore may not have preserved the signing entitlement. Keyboard text return cannot be guaranteed.", systemImage: "exclamationmark.triangle")
            .font(.footnote).foregroundStyle(.orange)
        } else if !self.permissionService.hasFullAccess {
          Text("Switch to the Altboard keyboard once, then return here and recheck Full Access.")
            .font(.footnote).foregroundStyle(.secondary)
        }
      }
    }
    .navigationTitle("Setup")
    .navigationBarTitleDisplayMode(.inline)
    .navigationDestination(isPresented: self.$showsModels) {
      ModelsView()
    }
  }

  private static let defaultLanguage = AppLanguageConfig.fallback

  @AppStorage(SharedKey.appLanguage) private var selectedAppLanguage = defaultLanguage
  @AppStorage(SharedKey.hasUsableModel, store: AppGroup.sharedDefaults ?? .standard)
  private var hasUsableModel = false
  @AppStorage(SharedKey.parakeetV3NeedsRedownload, store: AppGroup.sharedDefaults ?? .standard)
  private var parakeetV3NeedsRedownload = false
  @SceneStorage(ModelTab.storageKey) private var modelsTab = ModelTab.speechRecognition
  @EnvironmentObject private var permissionService: PermissionService
  @EnvironmentObject private var pipTutorialService: PiPTutorialService
  @State private var showsModels = false

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
