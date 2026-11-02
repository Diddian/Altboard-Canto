import SwiftUI

struct DictationSettingsView: View {
  var body: some View {
    Form {
      Section {
        Toggle("Active Session", isOn: self.sessionBinding)
          .tint(.orange)
        Picker("Auto-Stop", selection: self.$selectedAutoStopPolicy) {
          ForEach(SessionAutoStopPolicy.allCases, id: \.self) { policy in
            Text(LocalizedStringKey(policy.displayNameKey)).tag(policy)
          }
        }
        NavigationLink("Active Session Info") {
          SessionInfoView()
        }
      } footer: {
        Text("An active session lets your keyboard start recording without switching apps. The orange microphone indicator is expected.")
      }
    }
    .navigationTitle("Dictation")
    .navigationBarTitleDisplayMode(.inline)
    .onChange(of: self.selectedAutoStopPolicy) { _, policy in
      SharedSettings().sessionAutoStopPolicy = policy
      if self.speechService.isSessionActive {
        self.speechService.session.updateTimeout()
      }
    }
  }

  @EnvironmentObject private var speechService: SpeechRecognitionService
  @State private var selectedAutoStopPolicy = SharedSettings().sessionAutoStopPolicy

  private var sessionBinding: Binding<Bool> {
    Binding(
      get: { self.speechService.isSessionActive },
      set: { enabled in
        if enabled {
          try? self.speechService.session.startSession()
        } else {
          self.speechService.session.endSession()
        }
      }
    )
  }
}

struct TextAISettingsView: View {
  var body: some View {
    Form {
      TextOutputSection()
    }
    .navigationTitle("Text & AI")
    .navigationBarTitleDisplayMode(.inline)
  }
}

struct HelpSettingsView: View {
  var body: some View {
    Form {
      Section {
        NavigationLink("Setup & Permissions") {
          SetupView()
        }
        NavigationLink("Diagnostics") {
          DiagnosticsView()
        }
      }
      FeedbackSection()
    }
    .navigationTitle("Help")
    .navigationBarTitleDisplayMode(.inline)
  }
}

struct GeneralSettingsView: View {
  var body: some View {
    Form {
      Section {
        NavigationLink {
          AppLanguageListView()
        } label: {
          LabeledContent("App Language") {
            Text(verbatim: nativeLanguageNames[self.appLanguage] ?? self.appLanguage)
              .foregroundStyle(.secondary)
          }
        }
      }
    }
    .navigationTitle("General")
    .navigationBarTitleDisplayMode(.inline)
  }

  @AppStorage(SharedKey.appLanguage) private var appLanguage = AppLanguageConfig.fallback
}

struct AboutSettingsView: View {
  var body: some View {
    Form {
      Section("About") {
        #if APPSTORE
        FullVersionRow()
        #endif
        LabeledContent("Version", value: Bundle.main.infoDictionary?[
          "CFBundleShortVersionString"
        ] as? String ?? "Unknown")
      }
    }
    .navigationTitle("About")
    .navigationBarTitleDisplayMode(.inline)
  }
}
