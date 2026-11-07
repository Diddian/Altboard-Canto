import SwiftUI

enum DictationSettingsRows {
  case all
  case session
  case meeting
}

struct DictationSettingsView: View {
  var inline = false
  var rows: DictationSettingsRows = .all
  @State private var showsOutput = false

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
    switch self.rows {
    case .session:
      self.sessionRows
    case .meeting:
      EmptyView()
    case .all:
      if self.inline {
        self.sessionRows
        self.liveRows
        self.outputRows
        self.correctionsLink
      } else {
        Section("Recording") { self.sessionRows }
        Section("Live Speech to Text") { self.liveRows }
        Section("Output") { VoiceOutputSettingsView(inline: true) }
        Section("Word Corrections") {
          self.correctionsLink
        }
      }
    }
  }

  private var outputRows: some View {
    DisclosureGroup(isExpanded: self.$showsOutput) {
      if self.showsOutput {
        VoiceOutputSettingsView(inline: true)
      }
    } label: {
      Label("Output", systemImage: "character.bubble")
    }
  }

  private var correctionsLink: some View {
    NavigationLink {
      WordCorrectionsView()
    } label: {
      Label("Word Corrections", systemImage: "text.badge.checkmark")
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

