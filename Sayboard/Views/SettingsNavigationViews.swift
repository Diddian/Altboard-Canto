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
          Text("Recording")
        } footer: {
          Text("Auto-stop limits the active microphone session.")
        }
        Section {
          self.liveRows
        } header: {
          Text("Live Speech to Text")
        } footer: {
          Text("Offline updates are provisional; speed depends on the model and device.")
        }
        Section("Meetings") {
          self.meetingRows
          NavigationLink {
            CantoneseCorrectionsView()
          } label: {
            Label("Cantonese Recognition Corrections", systemImage: "text.badge.checkmark")
          }
        }
      }
    }

  }

  @ViewBuilder
  private var sessionRows: some View {
    Picker(selection: self.autoStopBinding) {
      ForEach(SessionAutoStopPolicy.allCases, id: \.self) { policy in
        Text(LocalizedStringKey(policy.displayNameKey)).tag(policy)
      }
    } label: {
      Label("Auto-Stop", systemImage: "timer")
    }
  }

  @ViewBuilder
  private var liveRows: some View {
    Toggle(isOn: self.liveBinding) {
      Label("Live Dictation", systemImage: "waveform")
    }
    if ProcessInfo.processInfo.physicalMemory < 8 * 1_073_741_824 {
      Text("Live updates may be slower on this device.")
        .font(.footnote).foregroundStyle(.secondary)
    }
  }

  @ViewBuilder
  private var meetingRows: some View {
    Toggle(isOn: self.$experimentalMeetingEnabled) {
      Label("Enable Meeting Recording", systemImage: "record.circle")
    }
    Text("Recordings stay on this device. Audio is saved in 15-minute parts.")
      .font(.footnote).foregroundStyle(.secondary)
  }

  private var liveBinding: Binding<Bool> {
    Binding(get: { self.experimentalLiveEnabled }, set: { enabled in
      guard self.experimentalLiveEnabled != enabled else { return }
      self.experimentalLiveEnabled = enabled
      SharedSettings().experimentalLiveDictationEnabled = enabled
    })
  }

  private var autoStopBinding: Binding<SessionAutoStopPolicy> {
    Binding(get: { self.selectedAutoStopPolicy }, set: { policy in
      guard self.selectedAutoStopPolicy != policy else { return }
      self.selectedAutoStopPolicy = policy
      SharedSettings().sessionAutoStopPolicy = policy
      if self.speechService.isSessionActive { self.speechService.session.updateTimeout() }
    })
  }

  @EnvironmentObject private var speechService: SpeechRecognitionService
  @State private var selectedAutoStopPolicy = SharedSettings().sessionAutoStopPolicy
  @State private var experimentalLiveEnabled = SharedSettings().experimentalLiveDictationEnabled
  @AppStorage(SharedKey.experimentalMeetingRecordEnabled,
              store: UserDefaults(suiteName: AppGroup.identifier))
  private var experimentalMeetingEnabled = false

}

// The Settings home owns the recording-session toggle.
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

struct HelpSettingsView: View {
  var body: some View {
    Form {
      FeedbackSection()
    }
    .navigationTitle("Help")
    .navigationBarTitleDisplayMode(.inline)
  }
}

