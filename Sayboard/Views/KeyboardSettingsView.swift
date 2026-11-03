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

      KeyboardTestPreview(
        kind: self.selectedKind,
        microphoneLayout: MicrophoneKeyboardLayout(
          rawValue: self.microphoneLayoutRaw
        ) ?? .defaultLayout,
        letterArrangement: LetterKeyArrangement(
          rawValue: self.letterArrangementRaw
        ) ?? .qwertz
      )
    } header: {
      Text("Keyboard")
    }
    .sensoryFeedback(.selection, trigger: self.sensoryPulse.count)
  }

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

private struct KeyboardTestPreview: View {
  let kind: KeyboardKind
  let microphoneLayout: MicrophoneKeyboardLayout
  let letterArrangement: LetterKeyArrangement

  @AppStorage(SharedKey.keyboardHapticsEnabled, store: UserDefaults(suiteName: AppGroup.identifier))
  private var keyboardHapticsEnabled = true
  @AppStorage(SharedKey.keyboardHapticStrength, store: UserDefaults(suiteName: AppGroup.identifier))
  private var hapticStrength = SharedSettings.defaultKeyboardHapticStrength
  @AppStorage(SharedKey.llmEnabled, store: UserDefaults(suiteName: AppGroup.identifier))
  private var llmEnabled = false
  @AppStorage(SharedKey.hasUsableLLMModel, store: UserDefaults(suiteName: AppGroup.identifier))
  private var hasUsableLLMModel = false
  @AppStorage(SharedKey.keyboardShowSettingsKey, store: UserDefaults(suiteName: AppGroup.identifier))
  private var showSettingsKey = true
  @AppStorage(SharedKey.keyboardShowOutputLanguageButton, store: UserDefaults(suiteName: AppGroup.identifier))
  private var showOutputLanguageButton = true
  @AppStorage(SharedKey.keyboardShowAIButton, store: UserDefaults(suiteName: AppGroup.identifier))
  private var showAIButton = true

  private var compact: Bool {
    self.kind == .standard && self.microphoneLayout == .compact
  }

  private var previewHeight: CGFloat {
    switch self.kind {
    case .standard: self.compact
      ? KeyboardLayoutGeometry.microphoneCompactHeight
      : KeyboardLayoutGeometry.microphoneDefaultHeight
    case .extended, .alphabetic: KeyboardLayoutGeometry.fullTypingHeight
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      if self.kind == .alphabetic {
        self.alphabetToolbar
          .padding(.top, KeyboardLayoutGeometry.alphabetToolbarTopInset)
          .padding(.bottom, KeyboardLayoutGeometry.alphabetToolbarBottomInset)
        VStack(spacing: KeyboardLayoutGeometry.alphabetRowSpacing) {
          self.letterRow(self.letterArrangement.rows[0], inset: KeyboardLayoutGeometry.alphabetEdgeInset)
          self.letterRow(self.letterArrangement.rows[1], inset: KeyboardLayoutGeometry.alphabetSecondInset)
          HStack(spacing: KeyboardLayoutGeometry.alphabetSpecialGap) {
            self.key("shift.fill", width: 50)
            HStack(spacing: 6) {
              ForEach(self.letterArrangement.rows[2], id: \.self) { self.letter($0) }
            }
            self.key("delete.left", width: 50)
          }
          .padding(.horizontal, 6.67)
        }
        .padding(.top, 0)
        self.alphabetBottomRow.padding(.top, KeyboardLayoutGeometry.alphabetRowSpacing)
      } else if self.kind == .extended {
        HStack(spacing: 6) {
          if self.showSettingsKey { self.key("gearshape", width: 45) }
          if self.showOutputLanguageButton { self.key("character.bubble", width: 45) }
          Spacer()
          self.key("mic.fill", width: 96, capsule: true)
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
        GeometryReader { geometry in
          let side = CGFloat(45)
          let micWidth = max(45, geometry.size.width - 2 * side
            - (2 * side + 6) - 3 * 6 - 8)
          ZStack {
            HStack(spacing: 6) {
              if self.showSettingsKey { self.key("gearshape", width: side) }
              if self.showOutputLanguageButton { self.key("character.bubble", width: side) }
              Spacer(minLength: 0)
              if self.showAIButton && self.llmEnabled && self.hasUsableLLMModel {
                self.key("sparkles", width: side)
              }
              self.key("delete.left", width: side)
            }
            if self.compact {
              self.key("mic.fill", width: micWidth)
                .frame(maxWidth: .infinity, alignment: .center)
            }
          }
        }.padding(.horizontal, 4).frame(height: 45)
        self.standardBottomRow.padding(.top, 6)
        Spacer(minLength: 0)
      }
    }
    .frame(height: self.previewHeight, alignment: .top)
    .frame(maxWidth: .infinity)
    .background(Color(uiColor: KeyboardPalette.backdrop), in: RoundedRectangle(cornerRadius: 14))
    .animation(.easeInOut(duration: 0.15), value: self.microphoneLayout)
    .accessibilityLabel("Interactive keyboard layout preview")
  }

  private var alphabetToolbar: some View {
    HStack(spacing: 6) {
      if self.showSettingsKey { self.key("gearshape", width: 48) }
      if self.showOutputLanguageButton { self.translatePreview }
      if self.showAIButton && self.llmEnabled && self.hasUsableLLMModel {
        self.key("sparkles", width: 48)
      }
      Spacer(minLength: 2)
      self.key("mic.fill", width: KeyboardLayoutGeometry.alphabetMicWidth, capsule: true)
    }
    .padding(.horizontal, 6.67)
    .frame(height: 45)
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
        .font(.system(size: 21, weight: .regular, design: .default))
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
      self.emojiPreviewKey(width: 48)
      self.labelKey("", height: 45)
      self.key("return.left", width: 102)
    }.padding(.horizontal, 6.67)
  }

  private var standardBottomRow: some View {
    HStack(spacing: 6) {
      self.emojiPreviewKey(width: 45)
      self.key("trash", width: 45)
      self.labelKey("", height: 45)
      self.key("return.left", width: 96)
    }.padding(.horizontal, 4)
  }

  private func emojiPreviewKey(width: CGFloat) -> some View {
    Button { self.tap() } label: {
      NativeEmojiGlyph()
        .fill(.primary, style: FillStyle(eoFill: true))
        .frame(width: 20.67, height: 20.67)
        .frame(width: width, height: 45)
        .background(Color(uiColor: KeyboardPalette.keyFill),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Test Emoji key haptic")
  }

  private func key(
    _ image: String, width: CGFloat, height: CGFloat = 45, capsule: Bool = false
  ) -> some View {
    Button { self.tap() } label: {
      Image(systemName: image)
        .font(.system(size: 18))
        .foregroundStyle(.primary)
        .frame(width: width, height: height)
        .background(Color(uiColor: KeyboardPalette.keyFill),
                    in: RoundedRectangle(cornerRadius: capsule || height == 96 ? height / 2 : 8,
                                        style: .continuous))
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
