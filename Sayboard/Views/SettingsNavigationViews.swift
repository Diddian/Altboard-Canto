import SwiftUI

struct DictationSettingsView: View {
  var inline = false

  var body: some View {
    Group {
      if self.inline {
        self.sections
      } else {
        Form { self.sections }
          .navigationTitle("Dictation")
          .navigationBarTitleDisplayMode(.inline)
      }
    }
  }

  @ViewBuilder
  var sections: some View {
    Group {
      Section {
        ActiveSessionToggle()
        Picker("Auto-Stop", selection: self.$selectedAutoStopPolicy) {
          ForEach(SessionAutoStopPolicy.allCases, id: \.self) { policy in
            Text(LocalizedStringKey(policy.displayNameKey)).tag(policy)
          }
        }
      } header: {
        HStack(alignment: .center, spacing: 8) {
          Text("Dictation")
          Spacer(minLength: 8)
          VStack(alignment: .trailing, spacing: 1) {
            Text("When active,")
            HStack(spacing: 3) {
              Image(systemName: "mic.fill")
                .foregroundStyle(.orange)
              Text("will appear")
            }
          }
          .font(.caption2)
          .foregroundStyle(.secondary)
          .textCase(nil)
          .accessibilityElement(children: .ignore)
          .accessibilityLabel("When active, the orange microphone indicator will appear")
        }
      }
      Section("Live Dictation & Meeting") {
        Toggle("Live Dictation", isOn: self.$experimentalLiveEnabled)
         Toggle("Meeting Record", isOn: self.$experimentalMeetingEnabled)
        if self.experimentalMeetingEnabled {
          NavigationLink("Meeting Recordings") {
            MeetingRecordsView()
          }
        }
       }
    }
    .onChange(of: self.selectedAutoStopPolicy) { _, policy in
      SharedSettings().sessionAutoStopPolicy = policy
      if self.speechService.isSessionActive {
        self.speechService.session.updateTimeout()
      }
    }
  }

  @EnvironmentObject private var speechService: SpeechRecognitionService
  @State private var selectedAutoStopPolicy = SharedSettings().sessionAutoStopPolicy
  @AppStorage(SharedKey.experimentalLiveDictationEnabled,
              store: UserDefaults(suiteName: AppGroup.identifier))
  private var experimentalLiveEnabled = false
  @AppStorage(SharedKey.experimentalMeetingRecordEnabled,
              store: UserDefaults(suiteName: AppGroup.identifier))
  private var experimentalMeetingEnabled = false

}

// Shared by the Settings home and Dictation page; one session owner/binding.
struct ActiveSessionToggle: View {
  @EnvironmentObject private var speechService: SpeechRecognitionService

  var body: some View {
    Toggle("Active Session", isOn: self.sessionBinding)
      .tint(.orange)
  }

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
