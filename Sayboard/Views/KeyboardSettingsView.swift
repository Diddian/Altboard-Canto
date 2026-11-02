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
          Toggle("Auto-capitalize sentences", isOn: self.$autoCapitalizationEnabled)
          if SharedSettings().preferredSpokenLanguages.contains("yue") {
            Picker("Cantonese romanization", selection: self.$romanizationRaw) {
              ForEach(CantoneseRomanizationScheme.allCases, id: \.self) { scheme in
                Text(scheme.displayName).tag(scheme.rawValue)
              }
            }
            Text("Chinese candidates appear while you type Latin characters. Tap a candidate to replace its romanization.")
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
          Text("QWERTZ is the default. Both arrangements keep the same iOS-style keys and microphone.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        Toggle("Haptic Feedback", isOn: self.$keyboardHapticsEnabled)
        Picker("Haptic engine", selection: self.$hapticDriverRaw) {
          ForEach(KeyboardHapticDriver.allCases, id: \.self) { driver in
            Text(driver.displayName).tag(driver.rawValue)
          }
        }
        Text("Core Haptics is the default because UIKit feedback was silent in the diagnostic test. The keyboard falls back to original Altboard's SwiftUI sensory feedback if iOS rejects Core Haptics.")
          .font(.footnote)
          .foregroundStyle(.secondary)
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
          Text("Strength chooses a discrete Taptic pulse: Tick, Soft, Light, Medium or Heavy. Tap keys in the preview to compare.")
            .font(.footnote)
            .foregroundStyle(.secondary)
          Text("Test the app and keyboard extension separately; Full Access may be needed.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .disabled(!self.keyboardHapticsEnabled)
        VStack(alignment: .leading, spacing: 6) {
          Text("Compare haptic engines").font(.footnote.weight(.medium))
          HStack {
            Button("SwiftUI") { KeyboardHaptics.key(enabled: true, technique: .sensory) }
            Button("Selection") { KeyboardHaptics.key(enabled: true, technique: .selection) }
            Button("Soft") { KeyboardHaptics.key(enabled: true, technique: .soft) }
            Button("Heavy") { KeyboardHaptics.key(enabled: true, technique: .heavy) }
          }
          .buttonStyle(.bordered)
          Text("The diagnostic log records requests even if the system produces no vibration.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
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
    .sensoryFeedback(.selection, trigger: self.sensoryPulse.count)
  }

  @StateObject private var sensoryPulse = KeyboardSensoryPulse.shared
  @AppStorage(SharedKey.keyboardHapticDriver, store: UserDefaults(suiteName: AppGroup.identifier))
  private var hapticDriverRaw = KeyboardHapticDriver.coreHaptics.rawValue

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
  @AppStorage(SharedKey.keyboardRomanizationScheme, store: UserDefaults(suiteName: AppGroup.identifier))
  private var romanizationRaw = CantoneseRomanizationScheme.jyutping.rawValue
}


private struct KeyboardHeightPreview: View {
  let kind: KeyboardKind
  let heightFactor: Double
  let letterArrangement: LetterKeyArrangement

  @AppStorage(SharedKey.keyboardHapticsEnabled, store: UserDefaults(suiteName: AppGroup.identifier))
  private var keyboardHapticsEnabled = true
  @AppStorage(SharedKey.keyboardHapticStrength, store: UserDefaults(suiteName: AppGroup.identifier))
  private var hapticStrength = 0.60
  @AppStorage(SharedKey.llmEnabled, store: UserDefaults(suiteName: AppGroup.identifier))
  private var llmEnabled = false
  @AppStorage(SharedKey.hasUsableLLMModel, store: UserDefaults(suiteName: AppGroup.identifier))
  private var hasUsableLLMModel = false

  private var compact: Bool { self.kind == .standard && self.heightFactor < 0.90 }
  private var previewHeight: CGFloat {
    let factor = CGFloat(self.heightFactor)
    if self.kind != .standard { return max(284, 312 * factor) }
    return factor < 0.90 ? 150 + (factor - 0.70) * 420 : 260 * factor
  }

  var body: some View {
    VStack(spacing: 0) {
      if self.kind == .alphabetic {
        self.alphabetToolbar
          .offset(y: -8)
        VStack(spacing: 11) {
          self.letterRow(self.letterArrangement.rows[0], inset: 6.67)
          self.letterRow(self.letterArrangement.rows[1], inset: 28)
          HStack(spacing: 14.67) {
            self.key("shift.fill", width: 50)
            HStack(spacing: 6) {
              ForEach(self.letterArrangement.rows[2], id: \.self) { self.letter($0) }
            }
            self.key("delete.left", width: 50)
          }
          .padding(.horizontal, 6.67)
        }
        .padding(.top, 0)
        self.alphabetBottomRow.padding(.top, 11)
      } else if self.kind == .extended {
        HStack(spacing: 6) {
          self.key("gearshape", width: 45)
          self.key("character.bubble", width: 45)
          Spacer()
          self.key("mic.fill", width: 96)
        }.padding(.horizontal, 6.67).frame(height: 57)
        VStack(spacing: 8.5) {
          self.previewTextRow(["1","2","3","4","5","6","7","8","9","0"])
          self.previewTextRow(["-","/",":",";","(",")","$","&","@","\""])
          HStack(spacing: 6) {
            self.labelKey("#+=", width: 53)
            ForEach([".",",","?","!","'"], id: \.self) { self.labelKey($0) }
            self.key("delete.left", width: 53)
          }.padding(.horizontal, 4)
        }
        self.standardBottomRow.padding(.top, 8.5)
      } else {
        Spacer(minLength: 0)
        if !self.compact {
          self.key("mic.fill", width: 96, height: 96)
            .padding(.bottom, 8)
        }
        HStack(spacing: 6) {
          self.key("gearshape", width: 45)
          self.key("character.bubble", width: 45)
          Spacer(minLength: 0)
          if self.compact { self.key("mic.fill", width: 96) }
          self.key("sparkles", width: 45)
          self.key("delete.left", width: 45)
        }.padding(.horizontal, 4)
        self.standardBottomRow.padding(.top, 6)
        Spacer(minLength: 0)
      }
    }
    .padding(.top, self.kind == .standard ? 0 : 0)
    .frame(height: self.previewHeight, alignment: .top)
    .frame(maxWidth: .infinity)
    .background(Color(uiColor: KeyboardPalette.backdrop), in: RoundedRectangle(cornerRadius: 14))
    .animation(.easeInOut(duration: 0.15), value: self.heightFactor)
    .accessibilityLabel("Interactive keyboard layout preview")
  }

  private var alphabetToolbar: some View {
    HStack(spacing: 6) {
      self.key("gearshape", width: 48)
      self.translatePreview
      if self.llmEnabled && self.hasUsableLLMModel {
        self.key("sparkles", width: 48)
      }
      Spacer(minLength: 2)
      self.key("mic.fill", width: 86)
    }
    .padding(.horizontal, 6.67)
    .frame(height: 46.33)
  }

  private var translatePreview: some View {
    Button { self.tap() } label: {
      VStack(spacing: 0) {
        Image(systemName: "translate").font(.system(size: 17))
        Text("AUTO").font(.system(size: 8, weight: .bold, design: .rounded))
      }
      .foregroundStyle(.primary)
      .frame(width: 48, height: 45)
      .background(Color(uiColor: KeyboardPalette.keyFill),
                  in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Test translation key haptic")
  }

  private func letterRow(_ letters: [String], inset: CGFloat) -> some View {
    HStack(spacing: 6) {
      ForEach(letters, id: \.self) { self.letter($0) }
    }
    .padding(.horizontal, inset)
  }

  private func letter(_ title: String) -> some View {
    Button { self.tap() } label: {
      Text(verbatim: title)
        .font(.system(size: 23, weight: .regular, design: .default))
        .foregroundStyle(.primary)
        .offset(y: -1.2)
        .frame(maxWidth: .infinity)
        .frame(height: 45)
        .background(Color(uiColor: KeyboardPalette.keyFill),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Test " + title + " key haptic")
  }

  private func previewTextRow(_ titles: [String]) -> some View {
    HStack(spacing: 6) {
      ForEach(titles, id: \.self) { self.labelKey($0) }
    }.padding(.horizontal, 4)
  }

  private var alphabetBottomRow: some View {
    HStack(spacing: 6) {
      self.labelKey("?123", width: 48)
      self.key("face.smiling", width: 48)
      self.labelKey("", height: 45)
      self.key("return.left", width: 102)
    }.padding(.horizontal, 6.67)
  }

  private var standardBottomRow: some View {
    HStack(spacing: 6) {
      self.key("face.smiling", width: 45)
      self.key("trash", width: 45)
      self.labelKey("", height: 45)
      self.key("return.left", width: 96)
    }.padding(.horizontal, 4)
  }

  private func key(_ image: String, width: CGFloat, height: CGFloat = 45) -> some View {
    Button { self.tap() } label: {
      Image(systemName: image)
        .font(.system(size: 18))
        .foregroundStyle(.primary)
        .frame(width: width, height: height)
        .background(Color(uiColor: KeyboardPalette.keyFill),
                    in: RoundedRectangle(cornerRadius: height == 96 ? 48 : 8, style: .continuous))
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Test " + image + " key haptic")
  }

  private func labelKey(_ title: String, width: CGFloat? = nil, height: CGFloat = 45) -> some View {
    Button { self.tap() } label: {
      Text(verbatim: title)
        .font(.system(size: 16))
        .foregroundStyle(.primary)
        .frame(maxWidth: width == nil ? .infinity : nil)
        .frame(width: width, height: height)
        .background(Color(uiColor: KeyboardPalette.keyFill),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Test " + (title.isEmpty ? "space" : title) + " haptic")
  }

  private func tap() {
    KeyboardHaptics.key(strength: self.hapticStrength, enabled: self.keyboardHapticsEnabled)
  }
}
