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
    SharedKey.keyboardRomanizationScheme,
    store: UserDefaults(suiteName: AppGroup.identifier)
  )
  private var romanizationRaw = CantoneseRomanizationScheme.jyutping.rawValue
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

  private var offersCantonese: Bool {
    SharedSettings().preferredSpokenLanguages.contains("yue")
  }

  private var romanization: CantoneseRomanizationScheme {
    CantoneseRomanizationScheme(rawValue: self.romanizationRaw) ?? .jyutping
  }

  private var trackedTextMatches: Bool {
    LiveCantoneseSafety.matches(
      buffer: self.composition.buffer,
      hostContext: self.proxy.documentContextBeforeInput()
    )
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
    VStack(spacing: 0) {
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
      .padding(.top, Self.rowSpacing.kbScaled)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .onAppear {
      self.refreshAutomaticShift()
      self.updateCandidates()
    }
    .onChange(of: self.autoCapitalize) { _, _ in self.refreshAutomaticShift() }
    .onChange(of: self.romanizationRaw) { _, _ in self.updateCandidates() }
    .onChange(of: self.keyboardState.textContextRevision) { _, _ in
      // Preserve our own typed buffer; discard only if host text or cursor changed.
      if !self.composition.isEmpty && !self.trackedTextMatches {
        self.clearComposition()
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
      if self.offersCantonese && !self.composition.isEmpty && !self.candidates.isEmpty {
        self.candidateStrip
      } else {
        KeyButton(content: .systemImage("gearshape"),
                  fixedWidth: self.chrome.sideButtonWidth) {
          if let url = DeepLink.settingsURL { self.proxy.openURL(url) }
        }

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

  private var candidateStrip: some View {
    ScrollView(.horizontal) {
      HStack(spacing: 5.kbScaled) {
        ForEach(self.candidates) { candidate in
          Button {
            KeyboardHaptics.key()
            self.choose(candidate)
          } label: {
            Text(verbatim: candidate.text)
              .font(.system(size: 20.kbScaled, weight: .regular))
              .foregroundStyle(.primary)
              .lineLimit(1)
              .frame(minWidth: 36.kbScaled)
            .padding(.horizontal, 4.kbScaled)
            .frame(height: 43.kbScaled)
          }
          .buttonStyle(.plain)
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
            : self.shiftActive ? "shift.fill" : "shift"),
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
          onHostDeletion: { self.handleHostDeletion() }
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
          onHostDeletion: { self.handleHostDeletion() }
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
      uppercase: self.shiftActive || self.capsLock,
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
    // All Latin typing reaches the host immediately. The offline IME only
    // suggests; it does not intercept ordinary English text.
    let tracksLetter = self.page == .letters
      && character.count == 1
      && character.allSatisfy { $0.isASCII && $0.isLetter }
    let tracksTone = self.page == .numbers
      && !self.composition.isEmpty
      && character.count == 1
      && character.allSatisfy { "123456".contains($0) }
    if self.offersCantonese && (tracksLetter || tracksTone)
      && self.composition.append(character) {
      self.proxy.insertText(character)
      self.updateCandidates()
    } else {
      self.clearComposition()
      self.proxy.insertText(character)
    }
    self.didInsertLiteral(character)
  }

  private func didInsertLiteral(_ character: String) {
    if !self.capsLock { self.shiftActive = false }
    if self.autoCapitalize && ".!?。！？\n".contains(character) {
      self.refreshAutomaticShift()
    }
  }

  private func updateCandidates() {
    self.candidates = self.offersCantonese && !self.composition.isEmpty
      ? JyutpingDictionary.shared.candidates(for: self.composition.buffer, scheme: self.romanization)
      : []
  }

  private func clearComposition() {
    self.composition.clear()
    self.candidates.removeAll()
  }

  /// When the suffix is a recognized Cantonese spelling, Backspace erases the
  /// whole visible token. Never delete guessed text after the cursor has moved.
  private func deleteCompositionCharacter() -> Bool {
    guard self.offersCantonese,
          self.trackedTextMatches,
          JyutpingDictionary.shared.hasExactEntry(for: self.composition.buffer)
    else { return false }
    let count = self.composition.buffer.count
    self.clearComposition()
    for _ in 0..<count { self.proxy.deleteBackward() }
    self.refreshAutomaticShift()
    return true
  }

  private func handleHostDeletion() {
    if !self.composition.isEmpty { _ = self.composition.backspace() }
    if !self.composition.isEmpty && !self.trackedTextMatches {
      self.clearComposition()
    } else {
      self.updateCandidates()
    }
    self.refreshAutomaticShift()
  }

  private func choose(_ candidate: JyutpingCandidate) {
    guard self.trackedTextMatches else {
      self.clearComposition()
      return
    }
    let count = self.composition.buffer.count
    self.clearComposition()
    for _ in 0..<count { self.proxy.deleteBackward() }
    self.proxy.insertText(candidate.text)
    JyutpingDictionary.shared.remember(candidate)
    self.refreshAutomaticShift()
  }

  private func handleSpace() {
    self.clearComposition()
    self.proxy.insertSpace()
    self.refreshAutomaticShift()
  }

  private func handleReturn() {
    self.clearComposition()
    self.proxy.insertText("\n")
    self.refreshAutomaticShift()
  }

  private func toggleNumberPage() {
    // Preserve the romanization suffix across ?123 so tone digits still work.
    self.page = self.page == .letters ? .numbers : .letters
  }

  private func refreshAutomaticShift() {
    guard !self.capsLock else { return }
    self.shiftActive = self.autoCapitalize
      && SentenceCapitalization.shouldUseUppercase(after: self.proxy.documentContextBeforeInput())
  }

  private func tapShift() {
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
