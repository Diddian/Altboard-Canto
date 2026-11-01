import SwiftUI

struct KeyboardSettingsView: View {

  @Binding var selectedKind: KeyboardKind

  var body: some View {
    Form {
      Section {
        Picker("Keyboard Type", selection: self.$selectedKind) {
          ForEach(KeyboardKind.allCases, id: \.self) { kind in
            Text(LocalizedStringKey(kind.displayNameKey)).tag(kind)
          }
        }
        if self.selectedKind == .alphabetic {
          Picker("English key order", selection: self.$letterArrangementRaw) {
            Text("QWERTZ").tag(LetterKeyArrangement.qwertz.rawValue)
            Text("QWERTY").tag(LetterKeyArrangement.qwerty.rawValue)
          }
          .pickerStyle(.segmented)
          Picker("Typing language", selection: self.$typingLanguageRaw) {
            Text("English").tag(KeyboardTypingLanguage.english.rawValue)
            Text("粵拼").tag(KeyboardTypingLanguage.jyutping.rawValue)
          }
          .pickerStyle(.segmented)
          Toggle("Auto-capitalize sentences", isOn: self.$autoCapitalizationEnabled)
          Text("QWERTZ is the default. Both arrangements keep the same iOS-style keys and microphone.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        Toggle("Haptic Feedback", isOn: self.$keyboardHapticsEnabled)
        VStack(alignment: .leading, spacing: 10) {
          HStack {
            Text("Haptic strength")
            Spacer()
            Text("\(Int(self.hapticStrength * 100))%")
              .monospacedDigit()
              .foregroundStyle(.secondary)
          }
          Slider(value: self.$hapticStrength, in: 0.15...1, step: 0.05)
            .accessibilityLabel("Haptic strength")
          Button("Test haptic") {
            KeyboardHaptics.key(strength: self.hapticStrength, enabled: self.keyboardHapticsEnabled)
          }
          .font(.footnote)
          Text("Tap the letter keys in the preview below to test haptic feedback at this strength.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .disabled(!self.keyboardHapticsEnabled)
        VStack(alignment: .leading, spacing: 12) {
          HStack {
            Text("Keyboard height")
            Spacer()
            Text("\(Int(self.heightScale * 100))%")
              .foregroundStyle(.secondary)
              .monospacedDigit()
          }
          Slider(value: self.$heightScale, in: 0.70...1.10, step: 0.02)
            .accessibilityLabel("Keyboard height")
          KeyboardHeightPreview(
            kind: self.selectedKind,
            heightFactor: self.heightScale,
            letterArrangement: LetterKeyArrangement(rawValue: self.letterArrangementRaw) ?? .qwertz
          )
          Text(self.selectedKind == .standard
            ? (self.heightScale < 0.90
              ? "Compact microphone matches the space bar width and shape."
              : "Only vertical whitespace changes; key sizes stay fixed.")
            : "Letter and symbol keys retain their normal size at every height.")
            .font(.footnote)
            .foregroundStyle(.secondary)
          Button("Reset to recommended height") { self.heightScale = 0.92 }
            .font(.footnote)
        }
      } footer: {
        Text("The duplicate globe key is now Emoji. Long-press Emoji to switch keyboards where required.")
      }
      Section {
        Toggle("“.” Shortcut", isOn: self.$periodShortcutEnabled)
      } footer: {
        Text("Double tapping the space bar will insert a period followed by a space.")
      }
    }
    .navigationTitle("Keyboard")
    .navigationBarTitleDisplayMode(.inline)
  }

  @AppStorage(SharedKey.keyboardHapticsEnabled, store: UserDefaults(suiteName: AppGroup.identifier))
  private var keyboardHapticsEnabled = true
  @AppStorage(SharedKey.keyboardHapticStrength, store: UserDefaults(suiteName: AppGroup.identifier))
  private var hapticStrength = 0.60
  @AppStorage(SharedKey.periodShortcutEnabled, store: UserDefaults(suiteName: AppGroup.identifier))
  private var periodShortcutEnabled = true
  @AppStorage(SharedKey.keyboardHeightScale, store: UserDefaults(suiteName: AppGroup.identifier))
  private var heightScale = 0.92
  @AppStorage(SharedKey.keyboardLetterArrangement, store: UserDefaults(suiteName: AppGroup.identifier))
  private var letterArrangementRaw = LetterKeyArrangement.qwertz.rawValue
  @AppStorage(SharedKey.keyboardAutoCapitalizationEnabled, store: UserDefaults(suiteName: AppGroup.identifier))
  private var autoCapitalizationEnabled = true
  @AppStorage(SharedKey.keyboardTypingLanguage, store: UserDefaults(suiteName: AppGroup.identifier))
  private var typingLanguageRaw = KeyboardTypingLanguage.english.rawValue
}


private struct KeyboardHeightPreview: View {
  let kind: KeyboardKind
  let heightFactor: Double
  let letterArrangement: LetterKeyArrangement
  @AppStorage(SharedKey.keyboardHapticsEnabled, store: UserDefaults(suiteName: AppGroup.identifier))
  private var keyboardHapticsEnabled = true
  @AppStorage(SharedKey.keyboardHapticStrength, store: UserDefaults(suiteName: AppGroup.identifier))
  private var hapticStrength = 0.60

  private var compact: Bool { kind == .standard && heightFactor < 0.90 }
  private var previewHeight: CGFloat {
    if kind != .standard {
      return max(284, 289.5 * CGFloat(heightFactor))
    }
    let factor = CGFloat(heightFactor)
    return factor < 0.90
      ? 150 + (factor - 0.70) * 420
      : 260 * factor
  }

  var body: some View {
    GeometryReader { geo in
      let gap: CGFloat = 6
      let rowsHeight: CGFloat = self.compact ? 96 : 198
      let inset = self.compact
        ? max(0, (geo.size.height - rowsHeight) / 2)
        : max(0, geo.size.height - rowsHeight - 4)

      VStack(spacing: gap) {
        if self.kind == .standard {
          if !self.compact {
            Image(systemName: "mic.fill")
              .font(.system(size: 29))
              .frame(width: 96, height: 96)
              .background(Color(.tertiarySystemFill),
                in: RoundedRectangle(cornerRadius: 48))
              .frame(maxWidth: .infinity)
          }
          self.standardControls(compact: self.compact)
        } else if self.kind == .alphabetic {
          HStack(spacing: 6) {
            self.key("gearshape")
            Spacer()
            Image(systemName: "mic")
              .frame(width: 88, height: 45)
              .background(Color(.tertiarySystemFill),
                in: RoundedRectangle(cornerRadius: 8.5))
          }
          ForEach(0..<3, id: \.self) { rowIndex in
            HStack(spacing: 4) {
              ForEach(self.letterArrangement.rows[rowIndex], id: \.self) { letter in
                Button {
                  KeyboardHaptics.key(
                    strength: self.hapticStrength, enabled: self.keyboardHapticsEnabled
                  )
                } label: {
                  Text(letter)
                    .font(.system(size: 20, weight: .regular))
                    .frame(maxWidth: .infinity)
                    .frame(height: 45)
                    .background(Color(.tertiarySystemFill),
                      in: RoundedRectangle(cornerRadius: 5.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Try \(letter) key haptic")
              }
            }
          }
        } else {
          self.standardControls(compact: true)
          ForEach(0..<3, id: \.self) { _ in
            HStack(spacing: 6) {
              ForEach(0..<8, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 6)
                  .fill(Color(.tertiarySystemFill))
                  .frame(height: 45)
              }
            }
          }
        }
        self.spaceRow
      }
      .padding(.top, self.kind == .standard ? inset : 0)
      .frame(maxWidth: .infinity, alignment: .top)
    }
    .frame(height: self.previewHeight)
    .padding(.horizontal, 4)
    .background(Color(.secondarySystemGroupedBackground),
      in: RoundedRectangle(cornerRadius: 14))
    .animation(.easeInOut(duration: 0.15), value: self.heightFactor)
    .accessibilityLabel("Preview of keyboard: every key keeps the same size")
  }

  private func standardControls(compact: Bool) -> some View {
    HStack(spacing: 6) {
      self.key("gearshape")
      self.key("character.bubble")
      if compact {
        Image(systemName: "mic.fill")
          .font(.system(size: 21))
          .frame(maxWidth: .infinity)
          .frame(height: 45)
          .background(Color(.tertiarySystemFill),
            in: RoundedRectangle(cornerRadius: 8.5))
      } else {
        Spacer(minLength: 0)
      }
      self.key("sparkles")
      self.key("delete.left")
    }
    .frame(height: 45)
  }

  private var spaceRow: some View {
    HStack(spacing: 6) {
      self.key("face.smiling")
      self.key("trash")
      Image(systemName: "space")
        .font(.system(size: 18))
        .frame(maxWidth: .infinity)
        .frame(height: 45)
        .background(Color(.tertiarySystemFill),
          in: RoundedRectangle(cornerRadius: 8.5))
      self.key("return.left", width: 96)
    }
    .frame(height: 45)
  }

  private func key(_ name: String, width: CGFloat = 45) -> some View {
    Button {
      KeyboardHaptics.key(strength: self.hapticStrength, enabled: self.keyboardHapticsEnabled)
    } label: {
      Image(systemName: name)
        .font(.system(size: 18))
        .frame(width: width, height: 45)
        .background(Color(.tertiarySystemFill),
          in: RoundedRectangle(cornerRadius: 8.5))
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Try \(name) key haptic")
  }
}
