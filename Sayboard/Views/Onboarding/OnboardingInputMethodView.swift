import SwiftUI

struct OnboardingInputMethodView: View {
  let onContinue: () -> Void

  var body: some View {
    OnboardingScreen {
      VStack(spacing: 8) {
        Text("Make the keyboard yours", tableName: "KeyboardSetup")
          .font(.title.bold())
        Text("Choose how you type. You can add voice next, or start typing offline straight away.", tableName: "KeyboardSetup")
          .foregroundStyle(.secondary)
      }
      .multilineTextAlignment(.center)
      .padding(.horizontal, 28)
      .padding(.top, 32)
      KeyboardInputSetupOptions(selection: self.$selection)
        .padding(.horizontal, 16)
        .padding(.top, 24)
    } actions: {
      OnboardingPrimaryButton(
        label: Text("Continue"),
        isEnabled: !self.selection.languages.isEmpty
      ) {
        self.selection.save()
        let settings = SharedSettings()
        if settings.defaults.object(forKey: SharedKey.keyboardKind) == nil {
          settings.keyboardKind = .alphabetic
        }
        FeatureDiagnostics.record(.keyboardSetup, .completed)
        self.onContinue()
      }
    }
    .onAppear { FeatureDiagnostics.record(.keyboardSetup, .started) }
  }

  @State private var selection = KeyboardInputSetupSelection()
}

/// The same options are used by first-run setup and the Keyboard settings page.
struct KeyboardInputSetupView: View {
  var body: some View {
    ScrollView {
      KeyboardInputSetupOptions(selection: self.$selection)
        .padding(16)
    }
    .background(Color(.systemGroupedBackground))
    .navigationTitle(Text("Typing languages and methods", tableName: "KeyboardSetup"))
    .navigationBarTitleDisplayMode(.inline)
    .onChange(of: self.selection) {
      guard !self.selection.languages.isEmpty else { return }
      self.selection.save()
    }
  }

  @State private var selection = KeyboardInputSetupSelection()
}

private struct KeyboardInputSetupSelection: Equatable {
  var languages = SharedSettings().preferredTypingLanguages
  var mode = ChineseInputMode(
    rawValue: SharedSettings().defaults.string(forKey: SharedKey.keyboardChineseInputMode) ?? ""
  ) ?? .phonetic
  var arrangement = SharedSettings().keyboardLetterArrangement

  func save() {
    let settings = SharedSettings()
    settings.preferredTypingLanguages = self.languages
    settings.defaults.set(self.mode.rawValue, forKey: SharedKey.keyboardChineseInputMode)
    settings.keyboardLetterArrangement = self.arrangement
    FeatureDiagnostics.record(.keyboardSetup, .selected)
  }
}

private struct KeyboardInputSetupOptions: View {
  @Binding var selection: KeyboardInputSetupSelection

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      OnboardingCard {
        VStack(alignment: .leading, spacing: 12) {
          Text("Typing languages", tableName: "KeyboardSetup").font(.headline)
          Text("Use more than one if you mix languages. This does not change the app language or voice languages.", tableName: "KeyboardSetup")
            .font(.footnote)
            .foregroundStyle(.secondary)
          ForEach(KeyboardSetupPolicy.coreLanguages, id: \.self) { language in
            Toggle(isOn: self.binding(for: language)) {
              Text(verbatim: self.languageName(language))
            }
            .disabled(self.selection.languages == [language])
          }
        }
        .padding(16)
      }
      if self.selection.languages.contains("yue") {
        OnboardingCard {
          VStack(alignment: .leading, spacing: 12) {
            Text("How do you type Chinese?", tableName: "KeyboardSetup").font(.headline)
            ForEach(ChineseInputMode.allCases, id: \.self) { mode in
              self.methodRow(mode)
            }
            Text("Quick and Cangjie accept both third- and fifth-generation codes. You do not have to choose a generation.", tableName: "KeyboardSetup")
              .font(.footnote)
              .foregroundStyle(.secondary)
            self.discovery
          }
          .padding(16)
        }
      }
      OnboardingCard {
        VStack(alignment: .leading, spacing: 12) {
          Picker(selection: self.$selection.arrangement) {
            Text("QWERTY (English)").tag(LetterKeyArrangement.qwerty)
            Text("QWERTZ").tag(LetterKeyArrangement.qwertz)
            Text("German (Ä Ö Ü ß)").tag(LetterKeyArrangement.german)
          } label: {
            Text("Key Order")
          }
          .pickerStyle(.menu)
          Text("Change these choices later in Settings → Keyboard → Typing languages and methods. The keyboard's input-method button also switches Chinese methods.", tableName: "KeyboardSetup")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(16)
      }
    }
  }

  @State private var response = ""

  private var discovery: some View {
    DisclosureGroup {
      VStack(alignment: .leading, spacing: 12) {
        Text("Type the code or radicals you would use for 你. For strokes, enter its first five strokes. We suggest a method only after an exact match.", tableName: "KeyboardSetup")
          .font(.footnote)
        TextField(text: self.$response) {
          Text("For example: nei5, OF, ONF or 丿丨丿乛丨", tableName: "KeyboardSetup")
        }
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .textFieldStyle(.roundedBorder)
        .onChange(of: self.response) {
          if self.response.count > 32 { self.response = String(self.response.prefix(32)) }
        }
        if let mode = KeyboardSetupPolicy.suggestedMethod(for: self.response) {
          HStack(alignment: .top) {
            Text(self.methodName(mode), tableName: "KeyboardSetup").font(.headline)
            Spacer()
            Button {
              self.selection.mode = mode
              self.response = ""
            } label: {
              Text("Use this method", tableName: "KeyboardSetup")
            }
            .buttonStyle(.bordered)
          }
        } else if !self.response.isEmpty {
          Text("No exact match yet. You can choose any method above; this short example cannot identify every spelling or generation.", tableName: "KeyboardSetup")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }
      .padding(.top, 10)
    } label: {
      Text("Not sure? Try a word", tableName: "KeyboardSetup")
    }
  }

  private func methodRow(_ mode: ChineseInputMode) -> some View {
    let isSelected = self.selection.mode == mode
    return Button {
      self.selection.mode = mode
    } label: {
      HStack(spacing: 12) {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
          .foregroundStyle(isSelected ? Color.accentColor : .secondary)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 4) {
          Text(self.methodName(mode), tableName: "KeyboardSetup").font(.headline)
          Text(verbatim: KeyboardSetupPolicy.example(for: mode))
            .font(.body.monospaced())
            .foregroundStyle(.secondary)
        }
        Spacer(minLength: 0)
      }
      .frame(minHeight: 52, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  private func binding(for language: String) -> Binding<Bool> {
    Binding(
      get: { self.selection.languages.contains(language) },
      set: { enabled in
        if enabled {
          if !self.selection.languages.contains(language) { self.selection.languages.append(language) }
        } else if self.selection.languages.count > 1 {
          self.selection.languages.removeAll { $0 == language }
        }
      }
    )
  }

  private func languageName(_ language: String) -> String {
    switch language {
    case "yue": "廣東話 · 香港繁體"
    case "de": "Deutsch"
    default: "English"
    }
  }

  private func methodName(_ mode: ChineseInputMode) -> LocalizedStringKey {
    switch mode {
    case .phonetic: "Cantonese spelling · 粵語拼音"
    case .quick: "Quick · 速成"
    case .cangjie: "Cangjie · 倉頡"
    case .stroke: "Strokes · 筆畫"
    }
  }
}
