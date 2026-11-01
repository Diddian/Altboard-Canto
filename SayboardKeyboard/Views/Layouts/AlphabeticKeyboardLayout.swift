import SwiftUI

/// QWERTZ / QWERTY keyboard with the existing mic and a built-in offline Jyutping IME.
struct AlphabeticKeyboardLayout: View {
  let proxy: KeyboardProxy
  @ObservedObject var keyboardState: KeyboardState

  @AppStorage(
    SharedKey.keyboardLetterArrangement,
    store: UserDefaults(suiteName: AppGroup.identifier)
  )
  private var arrangementRaw = LetterKeyArrangement.qwertz.rawValue
  @AppStorage(
    SharedKey.keyboardTypingLanguage,
    store: UserDefaults(suiteName: AppGroup.identifier)
  )
  private var typingLanguageRaw = KeyboardTypingLanguage.english.rawValue
  @AppStorage(
    SharedKey.keyboardAutoCapitalizationEnabled,
    store: UserDefaults(suiteName: AppGroup.identifier)
  )
  private var autoCapitalize = true

  @State private var page = AlphabeticPage.letters
  @State private var shiftActive = true
  @State private var capsLock = false
  @State private var lastShiftTap: Date?
  @State private var composition = JyutpingComposition()
  @State private var candidates = [JyutpingCandidate]()

  private var arrangement: LetterKeyArrangement {
    LetterKeyArrangement(rawValue: self.arrangementRaw) ?? .qwertz
  }

  private var isJyutping: Bool {
    self.typingLanguageRaw == KeyboardTypingLanguage.jyutping.rawValue
  }

  private var chrome: KeyboardChromeMetrics {
    KeyboardChromeMetrics(keyboardState: self.keyboardState)
  }

  /// Reference: IMG_9658.jpeg at inferred 3x scale (45pt keys, 11pt row gaps).
  private static let rowSpacing: CGFloat = 11
  private static let edgeInset: CGFloat = 6.67
  private static let secondInset: CGFloat = 28
  private static let specialGap: CGFloat = 14.67

  var body: some View {
    VStack(spacing: Self.rowSpacing.kbScaled) {
      self.toolbar
      VStack(spacing: Self.rowSpacing.kbScaled) {
        self.firstKeyRow
        self.secondKeyRow
        self.thirdKeyRow
      }

      KeyboardBottomRow(
        proxy: self.proxy,
        metrics: self.chrome,
        keyboardState: self.keyboardState,
        alphabeticModeLabel: self.page == .letters ? "?123" : "ABC",
        onAlphabeticModeSwitch: { self.toggleNumberPage() },
        onSpaceAction: { self.handleSpace() },
        onReturnAction: { self.handleReturn() }
      )
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .onAppear { self.refreshAutomaticShift() }
    .onChange(of: self.autoCapitalize) { _, _ in self.refreshAutomaticShift() }
    .onChange(of: self.typingLanguageRaw) { _, _ in
      // Settings may change the active input mode while the keyboard is visible.
      self.composition.clear()
      self.candidates.removeAll()
      self.page = .letters
      self.refreshAutomaticShift()
    }
    .onChange(of: self.keyboardState.textContextRevision) { _, _ in
      // An external cursor / host edit must never commit unconfirmed text.
      if !self.keyboardState.isRecording && !self.keyboardState.isProcessing {
        self.composition.clear()
        self.candidates.removeAll()
      }
      self.refreshAutomaticShift()
    }
    .onDisappear {
      self.composition.clear()
      self.candidates.removeAll()
    }
  }

  private var toolbar: some View {
    HStack(spacing: KeyboardChromeMetrics.buttonSpacing) {
      if self.isJyutping && !self.composition.isEmpty {
        self.languageToggle
        self.candidateStrip
      } else {
        KeyButton(content: .systemImage("gearshape"),
                  fixedWidth: self.chrome.sideButtonWidth) {
          if let url = DeepLink.settingsURL { self.proxy.openURL(url) }
        }

        self.languageToggle

        TranslateToggleButton(
          fixedWidth: self.chrome.sideButtonWidth,
          compactStyle: true,
          keyboardState: self.keyboardState
        )
        if self.keyboardState.showsAIButton {
          AIButton(
            fixedWidth: self.chrome.sideButtonWidth,
            onTap: { KeyboardActions.tapLLM(state: self.keyboardState, proxy: self.proxy) },
            onLongPress: { KeyboardActions.longPressLLM(state: self.keyboardState, proxy: self.proxy) },
            longPressEnabled: self.keyboardState.longPressLLMAction.isSet,
            isActive: self.keyboardState.showLLMActions
          )
        }
        Spacer(minLength: 2.kbScaled)
      }

      if self.keyboardState.hasFullAccess && self.keyboardState.isMicrophoneAuthorized
          && self.keyboardState.hasUsableModel {
        MicButtonWithPulse(
          sizing: .extended(width: 86.kbScaled),
          proxy: self.proxy,
          reservesPulseSpace: false,
          keyboardState: self.keyboardState
        )
      } else {
        KeyButton(content: .systemImage("mic.slash"), fixedWidth: 86.kbScaled) {
          if let url = DeepLink.setupMicURL ?? DeepLink.settingsURL {
            self.proxy.openURL(url)
          }
        }
        .accessibilityLabel("Open Altboard to enable speech recognition")
      }
    }
    .padding(.horizontal, Self.edgeInset.kbScaled)
    .frame(height: 46.33.kbScaled)
  }

  private var languageToggle: some View {
    KeyButton(
      content: .symbol(self.isJyutping ? "粵" : "EN", fontSize: 15),
      fixedWidth: self.chrome.sideButtonWidth
    ) {
      if self.isJyutping { self.commitCompositionIfNeeded() }
      self.typingLanguageRaw = self.isJyutping
        ? KeyboardTypingLanguage.english.rawValue
        : KeyboardTypingLanguage.jyutping.rawValue
      self.page = .letters
      self.refreshAutomaticShift()
    }
    .accessibilityLabel(self.isJyutping ? "Switch to English" : "Switch to Jyutping")
  }

  private var candidateStrip: some View {
    ScrollView(.horizontal) {
      HStack(spacing: 5.kbScaled) {
        Text(self.composition.buffer)
          .font(.system(size: 12.kbScaled, weight: .medium))
          .foregroundStyle(.secondary)
          .padding(.trailing, 3.kbScaled)
        ForEach(self.candidates) { candidate in
          Button {
            KeyboardHaptics.key()
            self.choose(candidate)
          } label: {
            VStack(spacing: 1.kbScaled) {
              Text(verbatim: candidate.text)
                .font(.system(size: 19.kbScaled))
                .lineLimit(1)
              Text(verbatim: candidate.romanization)
                .font(.system(size: 9.kbScaled))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .frame(minWidth: 36.kbScaled)
            .padding(.horizontal, 4.kbScaled)
            .frame(height: 43.kbScaled)
          }
          .buttonStyle(.plain)
        }
        if self.candidates.isEmpty {
          Text("無候選字")
            .font(.system(size: 12.kbScaled))
            .foregroundStyle(.secondary)
        }
      }
    }
    .scrollIndicators(.hidden)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  @ViewBuilder
  private var firstKeyRow: some View {
    switch self.page {
    case .letters: self.letterRow(self.arrangement.rows[0], inset: Self.edgeInset)
    case .numbers: self.characterRow(Self.numbersRow1)
    case .symbols: self.characterRow(Self.symbolsRow1)
    }
  }

  @ViewBuilder
  private var secondKeyRow: some View {
    switch self.page {
    case .letters: self.letterRow(self.arrangement.rows[1], inset: Self.secondInset)
    case .numbers: self.characterRow(Self.numbersRow2)
    case .symbols: self.characterRow(Self.symbolsRow2)
    }
  }

  @ViewBuilder
  private var thirdKeyRow: some View {
    switch self.page {
    case .letters:
      HStack(spacing: Self.specialGap.kbScaled) {
        KeyButton(
          content: .systemImage(self.capsLock ? "capslock.fill"
            : self.shiftActive && !self.isJyutping ? "shift.fill" : "shift"),
          fixedWidth: 50.kbScaled,
          fillOnPress: self.shiftActive || self.capsLock
        ) { self.tapShift() }
        .accessibilityLabel(self.capsLock ? "Caps Lock" : "Shift")

        HStack(spacing: KeyboardChromeMetrics.buttonSpacing) {
          ForEach(Array(self.arrangement.rows[2].enumerated()), id: \.offset) { index, letter in
            self.letterKey(letter, index: index, count: 7)
          }
        }
        RepeatDeleteButton(
          proxy: self.proxy,
          fixedWidth: 50.kbScaled,
          onDeleteIntercept: { self.deleteCompositionCharacter() },
          onHostDeletion: { self.refreshAutomaticShift() }
        )
      }
      .padding(.horizontal, Self.edgeInset.kbScaled)

    case .numbers, .symbols:
      HStack(spacing: KeyboardChromeMetrics.buttonSpacing) {
        KeyButton(content: .symbol("ABC", fontSize: 15), fixedWidth: 51.kbScaled) {
          self.page = .letters
        }
        KeyButton(
          content: .symbol(self.page == .numbers ? "#+=" : "123", fontSize: 15),
          fixedWidth: 49.kbScaled
        ) {
          self.page = self.page == .numbers ? .symbols : .numbers
        }
        ForEach([".", ",", "?", "!", "'"], id: \.self) { value in
          KeyButton(content: .symbol(value, fontSize: 19)) {
            self.handleCharacter(value)
          }
        }
        RepeatDeleteButton(
          proxy: self.proxy,
          fixedWidth: 48.kbScaled,
          onDeleteIntercept: { self.deleteCompositionCharacter() },
          onHostDeletion: { self.refreshAutomaticShift() }
        )
      }
      .padding(.horizontal, Self.edgeInset.kbScaled)
    }
  }

  private func letterRow(_ letters: [String], inset: CGFloat) -> some View {
    HStack(spacing: KeyboardChromeMetrics.buttonSpacing) {
      ForEach(Array(letters.enumerated()), id: \.offset) { index, letter in
        self.letterKey(letter, index: index, count: letters.count)
      }
    }
    .padding(.horizontal, inset.kbScaled)
    .frame(height: KeyboardChromeMetrics.keyHeight)
  }

  private func letterKey(_ letter: String, index: Int, count: Int) -> some View {
    AlphabeticLetterKey(
      letter: letter,
      uppercase: !self.isJyutping && (self.shiftActive || self.capsLock),
      column: index,
      rowCount: count
    ) { typed in
      self.handleCharacter(typed)
      self.lastShiftTap = nil
    }
  }

  private func characterRow(_ characters: [String]) -> some View {
    HStack(spacing: KeyboardChromeMetrics.buttonSpacing) {
      ForEach(characters, id: \.self) { character in
        KeyButton(content: .symbol(character, fontSize: 19),
                  showsCallout: true, calloutRowSpacing: Self.rowSpacing.kbScaled) {
          self.handleCharacter(character)
        }
      }
    }
    .padding(.horizontal, Self.edgeInset.kbScaled)
    .frame(height: KeyboardChromeMetrics.keyHeight)
  }

  private func handleCharacter(_ character: String) {
    if self.isJyutping && self.composition.append(character) {
      self.updateCandidates()
      return
    }
    self.commitCompositionIfNeeded()
    self.proxy.insertText(character)
    self.didInsertLiteral(character)
  }

  private func didInsertLiteral(_ character: String) {
    if !self.capsLock { self.shiftActive = false }
    if self.autoCapitalize && ".!?。！？\n".contains(character) {
      self.refreshAutomaticShift()
    }
  }

  private func updateCandidates() {
    self.candidates = self.composition.isEmpty
      ? [] : JyutpingDictionary.shared.candidates(for: self.composition.buffer)
  }

  private func deleteCompositionCharacter() -> Bool {
    guard self.isJyutping && self.composition.backspace() else { return false }
    self.updateCandidates()
    return true
  }

  private func choose(_ candidate: JyutpingCandidate) {
    self.proxy.insertText(candidate.text)
    JyutpingDictionary.shared.remember(candidate)
    self.composition.clear()
    self.candidates.removeAll()
  }

  private func commitCompositionIfNeeded() {
    guard !self.composition.isEmpty else { return }
    if let first = self.candidates.first {
      self.choose(first)
    } else {
      self.proxy.insertText(self.composition.buffer)
      self.composition.clear()
      self.candidates.removeAll()
    }
  }

  private func handleSpace() {
    if self.isJyutping && !self.composition.isEmpty {
      self.commitCompositionIfNeeded()
    } else {
      self.proxy.insertSpace()
      self.refreshAutomaticShift()
    }
  }

  private func handleReturn() {
    if self.isJyutping && !self.composition.isEmpty {
      self.commitCompositionIfNeeded()
    } else {
      self.proxy.insertText("\n")
      self.refreshAutomaticShift()
    }
  }

  private func toggleNumberPage() {
    self.page = self.page == .letters ? .numbers : .letters
  }

  private func refreshAutomaticShift() {
    guard !self.capsLock else { return }
    self.shiftActive = self.autoCapitalize
      && SentenceCapitalization.shouldUseUppercase(after: self.proxy.documentContextBeforeInput())
  }

  private func tapShift() {
    guard !self.isJyutping else { return }
    let now = Date()
    if let lastShiftTap, now.timeIntervalSince(lastShiftTap) < 0.38 {
      self.capsLock = !self.capsLock
      self.shiftActive = self.capsLock
      self.lastShiftTap = nil
    } else {
      if self.capsLock {
        self.capsLock = false
        self.shiftActive = false
      } else {
        self.shiftActive.toggle()
      }
      self.lastShiftTap = now
    }
  }

  private static let numbersRow1 = ["1","2","3","4","5","6","7","8","9","0"]
  private static let numbersRow2 = ["-","/",":",";","(",")","$","&","@","\""]
  private static let symbolsRow1 = ["[","]","{","}","#","%","^","*","+","="]
  private static let symbolsRow2 = ["_","\\","|","~","<",">","€","£","¥","•"]
}

private enum AlphabeticPage {
  case letters
  case numbers
  case symbols
}
