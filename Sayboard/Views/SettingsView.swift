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
  @State private var preferredSpokenLanguages = SharedSettings().preferredSpokenLanguages
  @State private var showsLowStorageWarning = false

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

      Section("Start Here") {
        SpeechLanguagesSettingsView(
          inline: true, rowsOnly: true,
          onPreferredLanguagesChanged: { self.preferredSpokenLanguages = $0 }
        )
        NavigationLink {
          SetupView()
        } label: {
          LabeledContent {
            Text(self.setupChecklist.isComplete ? "Ready" : "Check")
              .foregroundStyle(self.setupChecklist.isComplete ? .secondary : .orange)
          } label: {
            Label("Is My Microphone Ready?", systemImage: "mic.circle")
          }
        }
        NavigationLink {
          ModelsView()
        } label: {
          Label("Offline Speech Model", systemImage: "cpu")
        }
      }

      Section("Speech & AI") {
        NavigationLink {
          DictationSettingsView()
        } label: {
          Label("Speech to Text", systemImage: "waveform")
        }
        NavigationLink {
          VoiceOutputSettingsView()
        } label: {
          Label("Speech Cleanup & Translation", systemImage: "character.bubble")
        }
        NavigationLink {
          LLMSettingsView()
        } label: {
          Label("Text Cleanup & AI Actions", systemImage: "sparkles")
        }
      }

      Section("Keyboard") {
        NavigationLink {
          KeyboardSettingsView(
            selectedKind: self.keyboardKindBinding,
            cantoneseSelected: self.preferredSpokenLanguages.contains("yue")
          )
        } label: {
          LabeledContent {
            Text(LocalizedStringKey(self.selectedKeyboardKind.displayNameKey))
              .foregroundStyle(.secondary)
          } label: {
            Label("Keyboard Layout & Preview", systemImage: "keyboard")
          }
        }
        NavigationLink {
          KeyboardCustomizationView()
        } label: {
          Label("Customize Keys & Feedback", systemImage: "slider.horizontal.3")
        }
      }

      Section("Your Data") {
        NavigationLink {
          DataAndStorageSettingsView()
        } label: {
          Label("History & Storage", systemImage: "externaldrive")
        }
      }

      Section("App") {
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
      self.preferredSpokenLanguages = SharedSettings().preferredSpokenLanguages
      self.showsLowStorageWarning = DiskSpace.isLow()
        && !OperatingSystem.isBackgroundNeuralEngineBlocked
    }
  }
}
