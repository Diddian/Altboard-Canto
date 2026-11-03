import SwiftUI

enum DictationSettingsRows {
  case all
  case session
  case meeting
}

struct DictationSettingsView: View {
  var inline = false
  var rows: DictationSettingsRows = .all

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
      switch self.rows {
      case .session:
        self.sessionRows
      case .meeting:
        self.meetingRows
      case .all:
        Section {
          self.sessionRows
        } header: {
          Text("Dictation")
        }
        Section("Live Dictation & Meeting") {
          self.meetingRows
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

  @ViewBuilder
  private var sessionRows: some View {
    ActiveSessionToggle()
    Picker(selection: self.$selectedAutoStopPolicy) {
      ForEach(SessionAutoStopPolicy.allCases, id: \.self) { policy in
        Text(LocalizedStringKey(policy.displayNameKey)).tag(policy)
      }
    } label: {
      Label("Auto-Stop", systemImage: "timer")
    }
  }

  @ViewBuilder
  private var meetingRows: some View {
    Toggle(isOn: self.$experimentalLiveEnabled) {
      Label("Live Dictation", systemImage: "waveform")
    }
    Toggle(isOn: self.$experimentalMeetingEnabled) {
      Label("Meeting Record", systemImage: "record.circle")
    }
    if self.experimentalMeetingEnabled {
      NavigationLink {
        MeetingRecordsView()
      } label: {
        Label("Meeting Recordings", systemImage: "list.bullet.rectangle")
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
    Toggle(isOn: self.sessionBinding) {
      Label("Active Session", systemImage: "mic")
    }
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
        NavigationLink {
          SetupView()
        } label: {
          Label("Setup & Permissions", systemImage: "checkmark.shield")
        }
        NavigationLink {
          DiagnosticsView()
        } label: {
          Label("Diagnostics", systemImage: "stethoscope")
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
          LabeledContent {
            Text(verbatim: nativeLanguageNames[self.appLanguage] ?? self.appLanguage)
              .foregroundStyle(.secondary)
          } label: {
            Label("App Language", systemImage: "globe")
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
