import SwiftUI
import UIKit

/// The Settings home is a navigation hub. Detailed controls live in one
/// destination each; this keeps the first screen short and predictable.
struct SettingsView: View {
  var body: some View {
    Form {
      // Restore the original always-visible shortcut above setup/navigation.
      Section {
        ActiveSessionToggle()
      }

      if !self.setupChecklist.isComplete || self.showsLowStorageWarning {
        self.setupSection
      }

      #if APPSTORE
      PurchaseSection()
      #endif

      Section {
        NavigationLink {
          KeyboardSettingsView(selectedKind: self.keyboardKindBinding)
        } label: {
          HStack {
            Label("Keyboard", systemImage: "keyboard")
            Spacer()
            Text(LocalizedStringKey(self.selectedKeyboardKind.displayNameKey))
              .foregroundStyle(.secondary)
          }
        }
        NavigationLink {
          DictationSettingsView()
        } label: {
          Label("Dictation", systemImage: "mic")
        }
        NavigationLink {
          SpeechLanguagesSettingsView()
        } label: {
          Label("Speech & Languages", systemImage: "waveform")
        }
        NavigationLink {
          TextAISettingsView()
        } label: {
          Label("Text & AI", systemImage: "textformat")
        }
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
            Text("Finish Setup")
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
