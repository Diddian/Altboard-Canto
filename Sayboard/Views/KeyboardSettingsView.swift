import SwiftUI

struct KeyboardSettingsView: View {
  @Binding var selectedKind: KeyboardKind
  var inline = false

  @AppStorage(SharedKey.microphoneKeyboardLayout, store: UserDefaults(suiteName: AppGroup.identifier))
  private var microphoneLayoutRaw = MicrophoneKeyboardLayout.defaultLayout.rawValue
  @AppStorage(SharedKey.keyboardLetterArrangement, store: UserDefaults(suiteName: AppGroup.identifier))
  private var letterArrangementRaw = LetterKeyArrangement.qwertz.rawValue
  @AppStorage(SharedKey.keyboardAutoCapitalizationEnabled, store: AppGroup.sharedDefaults ?? .standard)
  private var autoCapitalize = true
  @AppStorage(SharedKey.periodShortcutEnabled, store: AppGroup.sharedDefaults ?? .standard)
  private var periodShortcut = true
  @AppStorage(SharedKey.keyboardHapticsEnabled, store: AppGroup.sharedDefaults ?? .standard)
  private var hapticsEnabled = true
  @AppStorage(SharedKey.keyboardHapticStrength, store: AppGroup.sharedDefaults ?? .standard)
  private var hapticStrength = SharedSettings.defaultKeyboardHapticStrength

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
      Picker(selection: self.$selectedKind) {
        ForEach(KeyboardKind.allCases, id: \.self) { kind in
          Text(LocalizedStringKey(kind.displayNameKey)).tag(kind)
        }
      } label: {
        Label("Keyboard Type", systemImage: "keyboard")
      }
      .pickerStyle(.menu)

      if self.selectedKind == .standard {
        Picker(selection: self.$microphoneLayoutRaw) {
          ForEach(MicrophoneKeyboardLayout.allCases, id: \.self) { layout in
            Text(layout.displayName).tag(layout.rawValue)
          }
        } label: {
          Label("Microphone Layout", systemImage: "mic")
        }
        .pickerStyle(.menu)
      }

      if self.selectedKind == .alphabetic {
        Picker(selection: self.$letterArrangementRaw) {
          Text("QWERTY (English)").tag(LetterKeyArrangement.qwerty.rawValue)
          Text("QWERTZ").tag(LetterKeyArrangement.qwertz.rawValue)
          Text("German (Ä Ö Ü ß)").tag(LetterKeyArrangement.german.rawValue)
        } label: {
          Label("Key Order", systemImage: "rectangle.split.3x1")
        }
        .pickerStyle(.menu)
      }
      if self.selectedKind == .alphabetic {
        Toggle("Auto-capitalization", isOn: self.$autoCapitalize)
        Toggle("Double-Space Period", isOn: self.$periodShortcut)
      }
      Toggle("Haptic Feedback", isOn: self.$hapticsEnabled)
      DisclosureGroup {
        Slider(value: self.$hapticStrength, in: 0.15...1.0, step: 0.05) {
          Text("Haptic Strength")
        }
        .disabled(!self.hapticsEnabled)
        Button("Reset Haptic Feedback", systemImage: "arrow.counterclockwise") {
          self.hapticsEnabled = true
          self.hapticStrength = SharedSettings.defaultKeyboardHapticStrength
          SharedSettings().keyboardHapticDriver = .coreHaptics
        }
      } label: {
        Label("Haptic Settings", systemImage: "hand.tap")
      }
      DisclosureGroup {
        KeyboardCustomizationView(inline: true)
      } label: {
        Label("Keyboard Customization", systemImage: "slider.horizontal.3")
      }
      KeyboardTestPreview(
        kind: self.selectedKind,
        microphoneLayout: MicrophoneKeyboardLayout(rawValue: self.microphoneLayoutRaw)
          ?? .defaultLayout,
        letterArrangement: LetterKeyArrangement(rawValue: self.letterArrangementRaw)
          ?? .qwertz
      )
      .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
      Text("Tap preview keys to test haptics. Extra Globe appears at the far left only when enabled.")
        .font(.footnote)
        .foregroundStyle(.secondary)
    } header: {
      Text("Keyboard")
    }

  }
}

private struct KeyboardTestPreview: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @ObservedObject private var sensoryPulse = KeyboardSensoryPulse.shared
  @State private var previewUppercase = false
  let kind: KeyboardKind
  let microphoneLayout: MicrophoneKeyboardLayout
  let letterArrangement: LetterKeyArrangement

  // UIKit alone decides whether an in-keyboard system switch is required.
  // Extra Globe is a separate, opt-in action-row shortcut.
  @AppStorage(SharedKey.needsInputModeSwitchKey, store: AppGroup.sharedDefaults ?? .standard)
  private var systemSwitchRequired = false
  @AppStorage(SharedKey.keyboardShowGlobeKey, store: AppGroup.sharedDefaults ?? .standard)
  private var showExtraGlobeKey = false
  @AppStorage(SharedKey.hasUsableLLMModel, store: UserDefaults(suiteName: AppGroup.identifier))
  private var hasUsableLLMModel = false
  @AppStorage(SharedKey.keyboardShowSettingsKey, store: UserDefaults(suiteName: AppGroup.identifier))
  private var showSettingsKey = true
  @AppStorage(SharedKey.keyboardShowOutputLanguageButton, store: UserDefaults(suiteName: AppGroup.identifier))
  private var showOutputLanguageButton = true
  private var outputKeyEnabled: Bool {
    self.showOutputLanguageButton
  }
  @AppStorage(SharedKey.keyboardShowAIButton, store: UserDefaults(suiteName: AppGroup.identifier))
  private var showAIButton = true

  private var compact: Bool {
    self.kind == .standard && self.microphoneLayout == .compact
  }

  private var previewHeight: CGFloat {
    KeyboardLayoutGeometry.height(kind: self.kind, microphoneLayout: self.microphoneLayout)
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
            self.shiftPreview
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
          if self.showExtraGlobeKey { self.key("globe", width: 45) }
          if self.showSettingsKey { self.key("gearshape", width: 45) }
          if self.outputKeyEnabled { self.key("character.bubble", width: 45) }
          if self.showAIButton {
            self.key("sparkles", width: 45)
              .opacity(self.hasUsableLLMModel ? 1 : 0.42)
          }
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
          let side: CGFloat = 45
          let leftCount = (self.showExtraGlobeKey ? 1 : 0)
            + (self.showSettingsKey ? 1 : 0)
            + (self.outputKeyEnabled ? 1 : 0)
          let rightCount = (self.showAIButton ? 1 : 0) + 1
          let leftWidth = CGFloat(leftCount) * side + CGFloat(max(0, leftCount - 1)) * 6
          let rightWidth = CGFloat(rightCount) * side + CGFloat(max(0, rightCount - 1)) * 6
          let micWidth = max(45, min(160, geometry.size.width
            - 2 * max(leftWidth, rightWidth) - 14))
          ZStack {
            HStack(spacing: 6) {
              if self.showExtraGlobeKey { self.key("globe", width: side) }
              if self.showSettingsKey { self.key("gearshape", width: side) }
              if self.outputKeyEnabled { self.key("character.bubble", width: side) }
              Spacer(minLength: 0)
              if self.showAIButton {
                self.key("sparkles", width: side)
                  .opacity(self.hasUsableLLMModel ? 1 : 0.42)
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
    .background(Color(uiColor: KeyboardPalette.backdrop),
                in: RoundedRectangle(cornerRadius: KeyboardLayoutGeometry.topCornerRadius,
                                     style: .continuous))
    .animation(self.reduceMotion ? nil : .easeInOut(duration: 0.15), value: self.microphoneLayout)
    .sensoryFeedback(.selection, trigger: self.sensoryPulse.count)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Keyboard preview; tap keys to test haptic feedback")
  }

  private var alphabetToolbar: some View {
    HStack(spacing: 6) {
      if self.showExtraGlobeKey { self.key("globe", width: 48) }
      if self.showSettingsKey { self.key("gearshape", width: 48) }
      if self.outputKeyEnabled { self.translatePreview }
      if self.showAIButton {
        self.key("sparkles", width: 48)
          .opacity(self.hasUsableLLMModel ? 1 : 0.42)
      }
      Spacer(minLength: 2)
      self.key("mic.fill", width: KeyboardLayoutGeometry.alphabetMicWidth, capsule: true)
    }
    .padding(.horizontal, 6.67)
    .frame(height: 45)
  }

  private var translatePreview: some View {
    Button { KeyboardHaptics.key() } label: {
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
    .accessibilityLabel("Output language preview")
  }

  private var shiftPreview: some View {
    Button {
      self.previewUppercase.toggle()
      KeyboardHaptics.key()
    } label: {
      Image(systemName: self.previewUppercase ? "shift.fill" : "shift")
        .font(.system(size: 18))
        .foregroundStyle(.primary)
        .frame(width: 50, height: 45)
        .background(Color(uiColor: KeyboardPalette.keyFill),
          in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }.buttonStyle(.plain).accessibilityLabel("Preview Shift")
  }

  private func letterRow(_ letters: [String], inset: CGFloat) -> some View {
    HStack(spacing: 6) {
      ForEach(letters, id: \.self) { self.letter($0) }
    }
    .padding(.horizontal, inset)
  }

  private func letter(_ title: String) -> some View {
    Button { KeyboardHaptics.key() } label: {
      Text(verbatim: self.previewUppercase ? title.uppercased() : title.lowercased())
        .font(.system(size: 21, weight: .regular, design: .default))
        .foregroundStyle(.primary)
        .offset(y: -1.2)
        .frame(maxWidth: .infinity)
        .frame(height: 45)
        .background(Color(uiColor: KeyboardPalette.keyFill),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    .buttonStyle(.plain)
    .accessibilityLabel(title + " preview")
  }

  private func previewTextRow(_ titles: [String]) -> some View {
    HStack(spacing: 6) {
      ForEach(titles, id: \.self) { self.labelKey($0) }
    }.padding(.horizontal, 4)
  }

  private var alphabetBottomRow: some View {
    HStack(spacing: 6) {
      self.labelKey("?123", width: 48)
      if self.systemSwitchRequired && !self.showExtraGlobeKey {
        self.key("globe", width: 48)
      }
      self.labelKey("", height: 45)
      self.key("return.left", width: 102)
    }.padding(.horizontal, 6.67)
  }

  private var standardBottomRow: some View {
    HStack(spacing: 6) {
      if self.systemSwitchRequired && !self.showExtraGlobeKey {
        self.key("globe", width: 45)
      }
      self.key("trash", width: 45)
      self.labelKey("", height: 45)
      self.key("return.left", width: 96)
    }.padding(.horizontal, 4)
  }

  private func key(
    _ image: String, width: CGFloat, height: CGFloat = 45, capsule: Bool = false
  ) -> some View {
    Button { KeyboardHaptics.key() } label: {
      Image(systemName: image)
        .font(.system(size: 18))
        .foregroundStyle(.primary)
        .frame(width: width, height: height)
        .background(Color(uiColor: KeyboardPalette.keyFill),
                    in: RoundedRectangle(cornerRadius: capsule || height == 96 ? height / 2 : 8,
                                        style: .continuous))
    }
    .buttonStyle(.plain)
    .accessibilityLabel(image + " preview")
  }

  private func labelKey(_ title: String, width: CGFloat? = nil, height: CGFloat = 45) -> some View {
    Button { KeyboardHaptics.key() } label: {
      Text(verbatim: title)
        .font(.system(size: 16))
        .foregroundStyle(.primary)
        .frame(maxWidth: width == nil ? .infinity : nil)
        .frame(width: width, height: height)
        .background(Color(uiColor: KeyboardPalette.keyFill),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    .buttonStyle(.plain)
    .accessibilityLabel(title.isEmpty ? "Space key preview" : title + " preview")
  }

}



