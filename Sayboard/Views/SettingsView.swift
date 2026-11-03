import SwiftUI
import UIKit

struct SettingsView: View {
  var body: some View {
    Form {
      if !self.setupChecklist.isComplete || self.showsLowStorageWarning {
        self.setupSection
      }

      #if APPSTORE
      PurchaseSection()
      #endif

      Section {
        SpeechLanguagesSettingsView(
          inline: true, rowsOnly: true,
          onPreferredLanguagesChanged: { self.preferredSpokenLanguages = $0 }
        )
        DictationSettingsView(inline: true, rows: .session)
        NavigationLink {
          VoiceOutputSettingsView()
        } label: {
          Label("Voice Output & Translation", systemImage: "waveform")
        }
        DictationSettingsView(inline: true, rows: .meeting)
        NavigationLink {
          ModelsView()
        } label: {
          Label("Offline Speech Model", systemImage: "cpu")
        }
        NavigationLink {
          TextAISettingsView()
        } label: {
          Label("Text & AI", systemImage: "textformat")
        }
      } header: {
        HStack(spacing: 6) {
          Text("Speech & Dictation")
          Spacer(minLength: 4)
          HStack(spacing: 3) {
            Text("When active,")
            Image(systemName: "mic.fill").foregroundStyle(.orange)
            Text("will appear")
          }
          .font(.system(size: 10))
          .lineLimit(1)
          .fixedSize(horizontal: true, vertical: false)
          .textCase(nil)
          .accessibilityElement(children: .ignore)
          .accessibilityLabel("When active, the orange microphone indicator will appear")
        }
      }
      KeyboardSettingsView(
        selectedKind: self.keyboardKindBinding,
        inline: true,
        cantoneseSelected: self.preferredSpokenLanguages.contains("yue")
      )

      Section {
        NavigationLink {
          HistoryStorageSettingsView()
        } label: {
          Label("History & Storage", systemImage: "clock.arrow.circlepath")
        }
      }

      Section {
        NavigationLink {
          HelpSettingsView()
        } label: {
          Label("Help", systemImage: "questionmark.circle")
        }
        NavigationLink {
          GeneralSettingsView()
        } label: {
          Label("General", systemImage: "gearshape")
        }
        NavigationLink {
          AboutSettingsView()
        } label: {
          Label("About", systemImage: "info.circle")
        }
      }
    }
    .navigationTitle("Settings")
    .navigationDestination(for: Route.self) { _ in
      SetupView()
    }
    .onAppear {
      self.preferredSpokenLanguages = SharedSettings().preferredSpokenLanguages
      self.showsLowStorageWarning = DiskSpace.isLow()
        && !OperatingSystem.isBackgroundNeuralEngineBlocked
    }
  }

  private enum Route: Hashable { case setup }

  @EnvironmentObject private var permissionService: PermissionService
  @AppStorage(SharedKey.hasUsableModel, store: UserDefaults(suiteName: AppGroup.identifier))
  private var hasUsableModel = false
  @AppStorage(SharedKey.keyboardKind, store: UserDefaults(suiteName: AppGroup.identifier))
  private var keyboardKindRaw = KeyboardKind.standard.rawValue
  @State private var showsLowStorageWarning = false
  @State private var preferredSpokenLanguages = SharedSettings().preferredSpokenLanguages

  private var selectedKeyboardKind: KeyboardKind {
    KeyboardKind(rawValue: self.keyboardKindRaw) ?? .standard
  }

  private var keyboardKindBinding: Binding<KeyboardKind> {
    Binding(
      get: { self.selectedKeyboardKind },
      set: { self.keyboardKindRaw = $0.rawValue }
    )
  }

  private var setupChecklist: SetupChecklist {
    SetupChecklist(permissions: self.permissionService, hasUsableModel: self.hasUsableModel)
  }

  private var setupSection: some View {
    Section {
      if !self.setupChecklist.isComplete {
        NavigationLink(value: Route.setup) {
          HStack {
            Label("Finish Setup", systemImage: "checklist")
            Spacer()
            Text(verbatim: "\(self.setupChecklist.remainingCount)")
              .foregroundStyle(.secondary)
              .accessibilityLabel(Text("\(self.setupChecklist.remainingCount) setup items remaining"))
          }
        }
      }
      if self.showsLowStorageWarning {
        Label {
          VStack(alignment: .leading, spacing: 2) {
            Text("Storage Is Getting Low")
            Text("Free some iPhone storage to avoid rebuilding the offline speech model.")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        } icon: {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
        }
      }
    } header: {
      Text("Action Required")
    }
  }
}
