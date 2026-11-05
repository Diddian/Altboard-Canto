import SwiftUI
import UIKit

/// Put the decisions users make first. Advanced controls stay in one clearly
/// named destination instead of a flat page of unrelated toggles.
struct SettingsView: View {
  @EnvironmentObject private var permissionService: PermissionService
  @AppStorage(SharedKey.hasUsableModel, store: UserDefaults(suiteName: AppGroup.identifier))
  private var hasUsableModel = false
  @AppStorage(SharedKey.keyboardKind, store: UserDefaults(suiteName: AppGroup.identifier))
  private var keyboardKindRaw = KeyboardKind.standard.rawValue
  @AppStorage(SharedKey.appLanguage) private var appLanguage = AppLanguageConfig.fallback
  @State private var showsLowStorageWarning = false
  @State private var showsStorage = false
  @State private var showsDictation = false
  @State private var showsAIActions = false

  private enum Route: Hashable { case setup }

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

  var body: some View {
    Form {
      if !self.setupChecklist.isComplete || self.showsLowStorageWarning {
        Section("Action Required") {
          if !self.setupChecklist.isComplete {
            NavigationLink(value: Route.setup) {
              LabeledContent {
                Text("\(self.setupChecklist.remainingCount) steps")
                  .foregroundStyle(.orange)
              } label: {
                Label("Complete Setup", systemImage: "checkmark.shield")
              }
            }
          }
          if self.showsLowStorageWarning {
            Label("Free storage before loading an offline model",
                  systemImage: "externaldrive.badge.exclamationmark")
              .foregroundStyle(.orange)
          }
        }
      }

      #if APPSTORE
      PurchaseSection()
      #endif

      Section("Speech & AI") {
        SpeechLanguagesSettingsView(inline: true, rowsOnly: true)
        ActiveSessionToggle()
        NavigationLink {
          ModelsView()
        } label: {
          Label("Speech Model", systemImage: "cpu")
        }
        NavigationLink {
          LLMModelsScreen()
        } label: {
          Label("Text Model", systemImage: "text.bubble")
        }
        DisclosureGroup(isExpanded: self.$showsDictation) {
          if self.showsDictation {
            DictationSettingsView(inline: true)
          }
        } label: {
          Label("Dictation", systemImage: "waveform")
        }
        NavigationLink {
          VoiceOutputSettingsView()
        } label: {
          Label("Output", systemImage: "character.bubble")
        }
        DisclosureGroup(isExpanded: self.$showsAIActions) {
          if self.showsAIActions {
            LLMSettingsView(inline: true)
          }
        } label: {
          Label("AI Actions", systemImage: "sparkles")
        }
      }

      KeyboardSettingsView(selectedKind: self.keyboardKindBinding, inline: true)

      Section {
        DisclosureGroup("History & Storage", isExpanded: self.$showsStorage) {
          if self.showsStorage {
            DataAndStorageSettingsView(inline: true)
          }
        }
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
        NavigationLink {
          HelpSettingsView()
        } label: {
          Label("Help", systemImage: "questionmark.circle")
        }
        LabeledContent("Version", value:
          Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")
      } header: {
        Text("App")
      } footer: {
        HStack {
          Spacer(minLength: 0)
          Link("Altboard-Canto · Source on GitHub",
               destination: URL(string: "https://github.com/Diddian/Altboard-Canto")!)
            .font(.footnote)
          Spacer(minLength: 0)
        }
      }
    }
    .navigationTitle("Settings")
    .navigationDestination(for: Route.self) { _ in SetupView() }
    .onAppear {
      self.showsLowStorageWarning = DiskSpace.isLow()
        && !OperatingSystem.isBackgroundNeuralEngineBlocked
    }
  }
}


