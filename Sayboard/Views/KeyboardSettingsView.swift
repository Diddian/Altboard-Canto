import SwiftUI

struct KeyboardSettingsView: View {

  @Binding var selectedKind: KeyboardKind
  var inline = false
  var cantoneseSelected = false

  var body: some View {
    Group {
      if self.inline {
        self.sections
      } else {
        Form { self.sections }
          .navigationTitle("Keyboard")
          .navigationBarTitleDisplayMode(.inline)
      }
    }
  }

  @ViewBuilder
  var sections: some View {
    Section {
      Picker("Keyboard Type", selection: self.$selectedKind) {
        ForEach(KeyboardKind.allCases, id: \.self) { kind in
          Text(LocalizedStringKey(kind.displayNameKey)).tag(kind)
        }
      }
      Toggle("Show Settings Key", isOn: self.$showSettingsKey)

      if self.selectedKind == .standard {
        Picker("Microphone Layout", selection: self.$microphoneLayoutRaw) {
          ForEach(MicrophoneKeyboardLayout.allCases, id: \.self) { layout in
            Text(layout.displayName).tag(layout.rawValue)
          }
        }
        .pickerStyle(.segmented)
      }

      if self.selectedKind == .alphabetic {
        Picker("Key Order", selection: self.$letterArrangementRaw) {
          Text("QWERTZ").tag(LetterKeyArrangement.qwertz.rawValue)
          Text("QWERTY").tag(LetterKeyArrangement.qwerty.rawValue)
        }
        .pickerStyle(.segmented)
        Toggle("Auto-capitalize Sentences", isOn: self.$autoCapitalizationEnabled)
        Toggle("Swipe Typing (English / German)", isOn: self.$swipeTypingEnabled)
        NavigationLink("All Keyboard Diagnostics") {
          DiagnosticsView()
        }
      }

      if self.cantoneseSelected || SharedSettings().preferredSpokenLanguages.contains("yue") {
        NavigationLink {
          CantoneseCorrectionsView()
        } label: {
          Label("Cantonese Word Corrections", systemImage: "text.badge.checkmark")
        }
      }

      Toggle("Haptic Feedback", isOn: self.$keyboardHapticsEnabled)
      if self.keyboardHapticsEnabled {
        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Text("Haptic Strength")
            Spacer()
            Text("\(Int(self.hapticStrength * 100))%")
              .monospacedDigit()
              .foregroundStyle(.secondary)
          }
          Slider(value: self.$hapticStrength, in: 0.15...1, step: 0.05)
            .accessibilityLabel("Haptic Strength")
          Button("Reset to Default (55%)") {
            self.hapticStrength = SharedSettings.defaultKeyboardHapticStrength
          }
          .font(.subheadline)
          .disabled(abs(self.hapticStrength - SharedSettings.defaultKeyboardHapticStrength) < 0.001)
        }
        Button("Test Haptic") {
          KeyboardHaptics.key(strength: self.hapticStrength, enabled: true)
        }
        Picker("Haptic Method", selection: self.$hapticDriverRaw) {
          ForEach(KeyboardHapticDriver.allCases, id: \.self) { driver in
            Text(driver.displayName).tag(driver.rawValue)
          }
        }
      }

      Toggle("Double-Space Period", isOn: self.$periodShortcutEnabled)

    } header: {
      Text("Keyboard")
    }
    .sensoryFeedback(.selection, trigger: self.sensoryPulse.count)

    Section("Live Keyboard Test") {
      TextField("Tap to open your active iOS keyboard", text: self.$testText, axis: .vertical)
        .lineLimit(2...5)
        .autocorrectionDisabled()
      Text("Choose Altboard with the system Globe key. This is the actual installed keyboard, not a drawn imitation.")
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
  }

  @State private var testText = ""
  @StateObject private var sensoryPulse = KeyboardSensoryPulse.shared
  @AppStorage(SharedKey.keyboardShowSettingsKey, store: UserDefaults(suiteName: AppGroup.identifier))
  private var showSettingsKey = true

  @AppStorage(SharedKey.microphoneKeyboardLayout, store: UserDefaults(suiteName: AppGroup.identifier))
  private var microphoneLayoutRaw = MicrophoneKeyboardLayout.defaultLayout.rawValue
  @AppStorage(SharedKey.keyboardHapticDriver, store: UserDefaults(suiteName: AppGroup.identifier))
  private var hapticDriverRaw = KeyboardHapticDriver.coreHaptics.rawValue
  @AppStorage(SharedKey.keyboardHapticsEnabled, store: UserDefaults(suiteName: AppGroup.identifier))
  private var keyboardHapticsEnabled = true
  @AppStorage(SharedKey.keyboardHapticStrength, store: UserDefaults(suiteName: AppGroup.identifier))
  private var hapticStrength = SharedSettings.defaultKeyboardHapticStrength
  @AppStorage(SharedKey.periodShortcutEnabled, store: UserDefaults(suiteName: AppGroup.identifier))
  private var periodShortcutEnabled = true
  @AppStorage(SharedKey.keyboardLetterArrangement, store: UserDefaults(suiteName: AppGroup.identifier))
  private var letterArrangementRaw = LetterKeyArrangement.qwertz.rawValue
  @AppStorage(SharedKey.keyboardAutoCapitalizationEnabled, store: UserDefaults(suiteName: AppGroup.identifier))
  private var autoCapitalizationEnabled = true
  @AppStorage(SharedKey.keyboardSwipeTypingEnabled, store: UserDefaults(suiteName: AppGroup.identifier))
  private var swipeTypingEnabled = false
}

