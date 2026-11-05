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
          Text("Microphone & Recording")
        } footer: {
          Text("Keep recording active only when you need it. Auto-Stop limits a recording session, not saved meeting length.")
        }
        Section {
          self.liveRows
        } header: {
          Text("Live Speech to Text")
        } footer: {
          Text("Recognition runs offline. Roughly 1.5-second updates are a target, not a guaranteed speed. Long recordings require a supported model.")
        }
        Section("Meetings") {
          self.meetingRows
          NavigationLink {
            ModelsView()
          } label: {
            Label("Offline Speech Model", systemImage: "cpu")
          }
          NavigationLink {
            CantoneseCorrectionsView()
          } label: {
            Label("Cantonese Recognition Corrections", systemImage: "text.badge.checkmark")
          }
        }
      }
    }
    .onAppear { self.experimentalLiveEnabled = SharedSettings().experimentalLiveDictationEnabled }
    .onChange(of: self.experimentalLiveEnabled) { _, enabled in
      SharedSettings().experimentalLiveDictationEnabled = enabled
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
  private var liveRows: some View {
    Toggle(isOn: self.$experimentalLiveEnabled) {
      Label("Live Dictation", systemImage: "waveform")
    }
    if ProcessInfo.processInfo.physicalMemory < 8 * 1_073_741_824 {
      Label {
        Text("This iPhone has less than 8 GB of RAM. Live Dictation is off by default because rapid updates may be slow. You can still enable it and test.")
      } icon: {
        Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
      }
      .font(.footnote)
    } else {
      Text("This iPhone meets the initial 8 GB memory recommendation. Actual dictation speed still depends on the downloaded model and thermal conditions.")
        .font(.footnote).foregroundStyle(.secondary)
    }
  }

  @ViewBuilder
  private var meetingRows: some View {
    Toggle(isOn: self.$experimentalMeetingEnabled) {
      Label("Enable Meeting Recording", systemImage: "record.circle")
    }
    NavigationLink {
      MeetingRecordsView()
    } label: {
      Label("Meeting Recordings", systemImage: "list.bullet.rectangle")
    }
    Text("Meeting audio rotates into 15-minute files; provisional transcript updates target about 8 seconds. Files and the combined transcript stay on-device.")
      .font(.footnote).foregroundStyle(.secondary)
  }

  @EnvironmentObject private var speechService: SpeechRecognitionService
  @State private var selectedAutoStopPolicy = SharedSettings().sessionAutoStopPolicy
  @State private var experimentalLiveEnabled = SharedSettings().experimentalLiveDictationEnabled
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
