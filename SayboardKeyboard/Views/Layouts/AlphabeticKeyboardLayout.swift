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
  @State private var lastInputWasSymbol = false
  @State private var shiftActive = true
  @State private var capsLock = false
  @State private var lastShiftTap: Date?
  @State private var composition = JyutpingComposition()
  @State private var candidates = [JyutpingCandidate]()
  @State private var expandedCandidates = [JyutpingCandidate]()
  @State private var showsCandidateGrid = false
  @State private var activeLatinWord: String?
  @State private var latinSuggestions = [LatinWordSuggestion]()
  @State private var latinRefreshTask: Task<Void, Never>?
  @AppStorage(
    SharedKey.keyboardTouchDebugOverlay,
    store: UserDefaults(suiteName: AppGroup.identifier)
  )
  private var showTouchDebug = false

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
  private static let rowSpacing = KeyboardLayoutGeometry.alphabetRowSpacing
  private static let edgeInset = KeyboardLayoutGeometry.alphabetEdgeInset
  private static let secondInset = KeyboardLayoutGeometry.alphabetSecondInset
  private static let specialGap = KeyboardLayoutGeometry.alphabetSpecialGap

  var body: some View {
    VStack(spacing: 0) {
      self.toolbar
        // Keep every toolbar button completely inside the keyboard's
        // clipping bounds. A negative offset cut the mic and icons off.
        .padding(.top, KeyboardLayoutGeometry.alphabetToolbarTopInset.kbScaled)
        .padding(.bottom, KeyboardLayoutGeometry.alphabetToolbarBottomInset.kbScaled)
      // The 11pt visual row gaps become two 5.5pt touch bands. All letter
      // space is routed, while key graphics keep their exact positions.
      VStack(spacing: 0) {
        self.firstKeyRow
          .frame(height: KeyboardChromeMetrics.keyHeight + Self.rowSpacing.kbScaled / 2,
                 alignment: .top)
        self.secondKeyRow
          .frame(height: KeyboardChromeMetrics.keyHeight + Self.rowSpacing.kbScaled,
                 alignment: .center)
        self.thirdKeyRow
          .frame(height: KeyboardChromeMetrics.keyHeight + Self.rowSpacing.kbScaled / 2,
                 alignment: .bottom)
      }

      KeyboardBottomRow(
        proxy: self.proxy,
        metrics: self.chrome,
        keyboardState: self.keyboardState,
        alphabeticModeLabel: self.page == .letters ? "?123" : "ABC",
        onAlphabeticModeSwitch: { self.toggleNumberPage() },
        showsAlphabetIndicator: self.page == .letters,
        onSpaceAction: { self.handleSpace() },
        onReturnAction: { self.handleReturn() }
      )
      .padding(.top, Self.rowSpacing.kbScaled)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .overlay(alignment: .top) {
      if self.showsCandidateGrid, !self.expandedCandidates.isEmpty,
         self.page == .letters {
        self.expandedCandidateGrid
          .padding(.top, (
            KeyboardLayoutGeometry.alphabetToolbarTopInset
            + KeyboardLayoutGeometry.keyHeight
            + KeyboardLayoutGeometry.alphabetToolbarBottomInset
          ).kbScaled)
          .zIndex(10)
      }
    }
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
      self.updateCandidates()
    }
    .onDisappear {
      self.latinRefreshTask?.cancel()
      self.activeLatinWord = nil
      self.latinSuggestions.removeAll()
      self.composition.clear()
      self.candidates.removeAll()
      self.expandedCandidates.removeAll()
      self.showsCandidateGrid = false
    }
  }

  private var toolbar: some View {
    HStack(spacing: KeyboardChromeMetrics.buttonSpacing) {
      if self.keyboardState.showLLMActions {
        KeyboardLLMActionsToolbar(proxy: self.proxy, keyboardState: self.keyboardState)
      } else if self.page == .letters &&
          ((self.offersCantonese && !self.composition.isEmpty) || self.activeLatinWord != nil) {
        // The full toolbar becomes an iOS-style prediction strip for the
        // currently typed word, in Cantonese, German, English or another
        // available preferred spellchecker language. Hide mic and controls.
        self.candidateStrip
          .transition(.opacity)
        if self.offersCantonese && !self.composition.isEmpty {
          Button {
            self.showsCandidateGrid.toggle()
            if self.showsCandidateGrid {
              self.expandedCandidates = JyutpingDictionary.shared.candidates(
                for: self.composition.buffer, scheme: self.romanization, limit: 200
              )
            }
          } label: {
            Image(systemName: self.showsCandidateGrid ? "chevron.up" : "chevron.down")
              .font(.system(size: 12.kbScaled, weight: .semibold))
              .foregroundStyle(.secondary)
              .frame(width: 29.kbScaled, height: KeyboardChromeMetrics.keyHeight)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityLabel(self.showsCandidateGrid ? "Collapse candidates" : "Show all Chinese candidates")
        }
      } else {
        if self.keyboardState.showSettingsKey {
          KeyButton(content: .systemImage("gearshape"),
                    fixedWidth: self.chrome.sideButtonWidth) {
            if let url = DeepLink.settingsURL { self.proxy.openURL(url) }
          }
        }

        TranslateToggleButton(
          fixedWidth: self.chrome.sideButtonWidth,
          compactStyle: true,
          keyboardState: self.keyboardState,
          onHiddenSettings: self.keyboardState.showSettingsKey ? nil : {
            if let url = DeepLink.settingsURL { self.proxy.openURL(url) }
          }
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

        if self.keyboardState.hasFullAccess && self.keyboardState.isMicrophoneAuthorized
            && self.keyboardState.hasUsableModel {
          MicAnimatedButton(
            sizing: .alphabet,
            proxy: self.proxy,
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
    }
    .padding(.horizontal, Self.edgeInset.kbScaled)
    .frame(height: KeyboardChromeMetrics.keyHeight)
    .animation(.easeOut(duration: 0.16), value: self.composition.isEmpty)
  }

  private var currentLiteral: String {
    if self.offersCantonese, !self.composition.isEmpty, self.trackedTextMatches,
       let context = self.proxy.documentContextBeforeInput() {
      return String(context.suffix(self.composition.buffer.count))
    }
    return self.activeLatinWord ?? self.composition.buffer
  }

  /// Three equally sized iOS-style suggestion slots per screen, with a
  /// scrolling continuation for additional Chinese phrases. Each separator
  /// is 1pt wide and 24pt tall, not a full-height list divider.
  private var candidateStrip: some View {
    GeometryReader { geometry in
      let width = geometry.size.width / 3
      let corrected = EnglishCaseSuggestion.replacement(for: self.currentLiteral)
      let firstCantoneseSlot = corrected == nil ? 1 : 2

      ScrollView(.horizontal) {
        HStack(spacing: 0) {
          self.suggestionCell(self.currentLiteral, width: width, showDivider: true) {
            self.latinRefreshTask?.cancel()
            self.activeLatinWord = nil
            self.latinSuggestions.removeAll()
            self.clearComposition()
            KeyboardInputTrace.record(.latinKept)
          }

          if let corrected {
            self.suggestionCell(corrected, width: width, showDivider: true) {
              self.chooseLatinSuggestion(corrected)
            }
          }

          ForEach(Array(self.candidates.enumerated()), id: \.offset) { index, candidate in
            self.suggestionCell(
              candidate.text,
              width: width,
              showDivider: (firstCantoneseSlot + index) % 3 != 2
            ) {
              self.choose(candidate)
            }
          }

          ForEach(Array(self.latinSuggestions.enumerated()), id: \.offset) { index, suggestion in
            self.suggestionCell(
              suggestion.text,
              width: width,
              showDivider: (firstCantoneseSlot + self.candidates.count + index) % 3 != 2
            ) {
              if self.chooseLatinSuggestion(suggestion.text) {
                LatinWordSuggestions.shared.remember(suggestion)
              }
            }
          }
        }
      }
      .scrollIndicators(.hidden)
    }
    .frame(height: KeyboardChromeMetrics.keyHeight)
  }

  private var expandedCandidateGrid: some View {
    ScrollView(.vertical) {
      LazyVGrid(
        columns: Array(repeating: GridItem(.flexible(), spacing: 3.kbScaled), count: 4),
        spacing: 3.kbScaled
      ) {
        ForEach(self.expandedCandidates) { candidate in
          Button {
            KeyboardHaptics.key()
            self.choose(candidate)
          } label: {
            Text(verbatim: candidate.text)
              .font(.system(size: 20.kbScaled))
              .foregroundStyle(.primary)
              .lineLimit(1)
              .minimumScaleFactor(0.7)
              .frame(maxWidth: .infinity, minHeight: 39.kbScaled)
              .background(
                RoundedRectangle(cornerRadius: 6.kbScaled)
                  .fill(Color(uiColor: KeyboardPalette.keyFill))
              )
          }
          .buttonStyle(.plain)
        }
      }
      .padding(6.kbScaled)
    }
    .scrollIndicators(.visible)
    .frame(height: 159.kbScaled)
    .background(
      Color(uiColor: KeyboardPalette.backdrop),
      in: RoundedRectangle(cornerRadius: 9.kbScaled, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 9.kbScaled, style: .continuous)
        .stroke(Color(uiColor: KeyboardPalette.suggestionSeparator), lineWidth: 1)
    }
    .padding(.horizontal, KeyboardLayoutGeometry.alphabetEdgeInset.kbScaled)
    .shadow(color: .black.opacity(0.20), radius: 4, y: 2)
  }

  private func suggestionCell(
    _ value: String,
    width: CGFloat,
    showDivider: Bool,
    onSelect: @escaping () -> Void
  ) -> some View {
    Button {
      KeyboardHaptics.key()
      onSelect()
    } label: {
      Text(verbatim: value)
        .font(.system(size: 19.kbScaled, weight: .regular))
        .foregroundStyle(Color(uiColor: KeyboardPalette.suggestionGlyph))
        .lineLimit(1)
        .minimumScaleFactor(0.72)
        .padding(.horizontal, 6.kbScaled)
        .frame(width: width, height: KeyboardChromeMetrics.keyHeight)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .overlay(alignment: .trailing) {
      if showDivider {
        Rectangle()
          .fill(Color(uiColor: KeyboardPalette.suggestionSeparator))
          .frame(
            width: KeyboardPalette.suggestionSeparatorWidth.kbScaled,
            height: KeyboardPalette.suggestionSeparatorHeight.kbScaled
          )
          .padding(.trailing, 0.67.kbScaled)
          .allowsHitTesting(false)
      }
    }
  }

  @ViewBuilder
  private var firstKeyRow: some View {
    switch self.page {
    case .letters:
      self.letterRow(self.arrangement.rows[0], inset: Self.edgeInset,
                     top: 0, bottom: Self.rowSpacing / 2)
    case .numbers: self.characterRow(Self.numbersRow1)
    case .symbols: self.characterRow(Self.symbolsRow1)
    }
  }

  @ViewBuilder
  private var secondKeyRow: some View {
    switch self.page {
    case .letters:
      self.letterRow(self.arrangement.rows[1], inset: Self.secondInset,
                     top: Self.rowSpacing / 2, bottom: Self.rowSpacing / 2)
    case .numbers: self.characterRow(Self.numbersRow2)
    case .symbols: self.characterRow(Self.symbolsRow2)
    }
  }

  @ViewBuilder
  private var thirdKeyRow: some View {
    switch self.page {
    case .letters:
      HStack(alignment: .bottom, spacing: Self.specialGap.kbScaled) {
        KeyButton(
          content: .systemImage(self.capsLock ? "capslock.fill"
            : self.shiftActive ? "shift.fill" : "shift"),
          fixedWidth: 50.kbScaled,
          fillOnPress: self.shiftActive || self.capsLock
        ) { self.tapShift() }
        .accessibilityLabel(self.capsLock ? "Caps Lock" : "Shift")

        self.letterRow(self.arrangement.rows[2], inset: 0,
                       top: Self.rowSpacing / 2, bottom: 0)
        RepeatDeleteButton(
          proxy: self.proxy,
          fixedWidth: 50.kbScaled,
          onDeleteIntercept: { self.deleteCompositionCharacter() },
          onHostDeletion: { self.handleHostDeletion() }
        )
      }
      .padding(.horizontal, KeyboardLayoutGeometry.alphabetSpecialRowInset.kbScaled)

    case .numbers, .symbols:
      GeometryReader { geometry in
        let inset = KeyboardLayoutGeometry.alphabetSymbolsRowInset.kbScaled
        let wideWidth = KeyboardLayoutGeometry.alphabetSymbolsWideKeyWidth.kbScaled
        let groupGap = KeyboardLayoutGeometry.alphabetSymbolsGroupGap.kbScaled
        let keyGap = KeyboardChromeMetrics.buttonSpacing
        let punctuationWidth = max(
          10.kbScaled,
          (geometry.size.width - 2 * inset - 2 * wideWidth
            - 2 * groupGap - 4 * keyGap) / 5
        )
        HStack(spacing: 0) {
          KeyButton(
            content: .symbol(self.page == .numbers ? "#+=" : "123", fontSize: 15),
            fixedWidth: wideWidth
          ) {
            self.page = self.page == .numbers ? .symbols : .numbers
          }
          Color.clear.frame(width: groupGap)
          HStack(spacing: keyGap) {
            ForEach([".", ",", "?", "!", "'"], id: \.self) { value in
              KeyButton(
                content: .symbol(self.nativeSymbolFace(value), fontSize: 19),
                fixedWidth: punctuationWidth
              ) {
                self.handleCharacter(value)
              }
            }
          }
          Color.clear.frame(width: groupGap)
          RepeatDeleteButton(
            proxy: self.proxy,
            fixedWidth: wideWidth,
            onDeleteIntercept: { self.deleteCompositionCharacter() },
            onHostDeletion: { self.handleHostDeletion() }
          )
        }
        .padding(.horizontal, inset)
      }
      .frame(height: KeyboardChromeMetrics.keyHeight)
    }
  }

  private var touchPredictionPrefix: String? {
    if self.offersCantonese && !self.composition.isEmpty {
      // Existing candidate romanization stores Jyutping. Do not apply the
      // wrong alphabet model to Yale or Yuetyam spellings.
      return self.romanization == .jyutping ? self.composition.buffer : nil
    }
    return self.activeLatinWord
  }

  private var touchPredictionWords: [String] {
    if self.offersCantonese && !self.composition.isEmpty {
      return self.romanization == .jyutping
        ? self.candidates.map(\.romanization) : []
    }
    return self.latinSuggestions.map(\.text)
  }

  private func letterRow(
    _ letters: [String], inset: CGFloat, top: CGFloat, bottom: CGFloat
  ) -> some View {
    AlphabeticTouchRow(
      letters: letters,
      uppercase: self.shiftActive || self.capsLock,
      horizontalInset: inset.kbScaled,
      topHitInset: top.kbScaled,
      bottomHitInset: bottom.kbScaled,
      typedContext: self.touchPredictionPrefix,
      completionWords: self.touchPredictionWords,
      showTouchDebug: self.showTouchDebug
    ) { typed in
      self.handleCharacter(typed)
      self.lastShiftTap = nil
    }
  }

  private func characterRow(_ characters: [String]) -> some View {
    HStack(spacing: KeyboardChromeMetrics.buttonSpacing) {
      ForEach(characters, id: \.self) { character in
        KeyButton(content: .symbol(self.nativeSymbolFace(character), fontSize: 19),
                  showsCallout: true, calloutRowSpacing: Self.rowSpacing.kbScaled) {
          self.handleCharacter(character)
        }
      }
    }
    .padding(.horizontal, KeyboardLayoutGeometry.alphabetSymbolsRowInset.kbScaled)
    .frame(height: KeyboardChromeMetrics.keyHeight)
  }

  private func nativeSymbolFace(_ character: String) -> String {
    switch character {
    case "\"": "”"
    case "'": "’"
    default: character
    }
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
    } else {
      self.clearComposition()
      self.proxy.insertText(character)
    }
    self.lastInputWasSymbol = self.page != .letters
      && !character.allSatisfy({ $0.isNumber })
    self.didInsertLiteral(character)
    self.updateCandidates()
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
    if self.showsCandidateGrid {
      self.expandedCandidates = self.candidates.isEmpty ? [] : JyutpingDictionary.shared.candidates(
        for: self.composition.buffer, scheme: self.romanization, limit: 200
      )
    }

    let typed = self.page == .letters
      ? LatinWordSuggestionPolicy.trailingWord(in: self.proxy.documentContextBeforeInput())
      : nil
    self.activeLatinWord = typed
    self.latinRefreshTask?.cancel()
    self.latinSuggestions.removeAll()
    guard let typed else { return }

    // Let key-down animation render before asking the installed OS
    // spellchecker for suggestions. Drop stale work during fast typing.
    let preferred = SharedSettings().preferredSpokenLanguages
    self.latinRefreshTask = Task { @MainActor in
      do { try await Task.sleep(for: .milliseconds(45)) } catch { return }
      guard !Task.isCancelled,
            self.activeLatinWord == typed,
            LatinWordSuggestionPolicy.trailingWord(
              in: self.proxy.documentContextBeforeInput()
            ) == typed else { return }
      let values = LatinWordSuggestions.shared.choices(for: typed, preferred: preferred)
      guard !Task.isCancelled, self.activeLatinWord == typed else { return }
      self.latinSuggestions = values
    }
  }

  private func clearComposition() {
    self.composition.clear()
    self.candidates.removeAll()
    self.expandedCandidates.removeAll()
    self.showsCandidateGrid = false
  }

  /// Delete the *last syllable* of a verified complete Cantonese spelling.
  /// gamyat → gam (remove yat), not an entire "gamyat" word. Unknown English
  /// remains normal character-by-character deletion via RepeatDeleteButton.
  private func deleteCompositionCharacter() -> Bool {
    guard self.offersCantonese, self.trackedTextMatches,
      let canonical = JyutpingDictionary.shared.exactRomanization(for: self.composition.buffer),
      let count = CantoneseSyllableEditing.lastSyllableLength(
        typed: self.composition.buffer, canonical: canonical
      )
    else { return false }

    self.composition.removeLast(count)
    KeyboardInputTrace.record(.syllableDeleted)
    // Update local state before changing the host; cursor changes can arrive
    // from the host asynchronously during this multi-character deletion.
    for _ in 0..<count { self.proxy.deleteBackward() }
    self.updateCandidates()
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

  @discardableResult
  private func chooseLatinSuggestion(_ text: String) -> Bool {
    let typed = self.currentLiteral
    guard LatinWordSuggestionPolicy.canReplace(
      typed, in: self.proxy.documentContextBeforeInput()
    ) else {
      self.clearComposition()
      self.updateCandidates()
      return false
    }
    self.latinRefreshTask?.cancel()
    self.clearComposition()
    self.activeLatinWord = nil
    self.latinSuggestions.removeAll()
    for _ in 0..<typed.count { self.proxy.deleteBackward() }
    self.proxy.insertText(text)
    KeyboardInputTrace.record(.latinSuggestionChosen)
    self.refreshAutomaticShift()
    self.updateCandidates()
    return true
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
    KeyboardInputTrace.record(.candidateChosen)
    JyutpingDictionary.shared.remember(candidate)
    self.refreshAutomaticShift()
    self.updateCandidates()
  }

  private func handleSpace() {
    // After punctuation, Space restores the Alphabet page. Digits retain
    // the numeric page to allow quantities and dates.
    let returnToLetters = self.page != .letters && self.lastInputWasSymbol
    self.clearComposition()
    self.proxy.insertSpace()
    if returnToLetters { self.page = .letters }
    self.lastInputWasSymbol = false
    KeyboardInputTrace.record(.spaceCommitted)
    self.refreshAutomaticShift()
    self.updateCandidates()
  }

  private func handleReturn() {
    self.lastInputWasSymbol = false
    self.clearComposition()
    self.proxy.insertText("\n")
    self.refreshAutomaticShift()
    self.updateCandidates()
  }

  private func toggleNumberPage() {
    // Preserve the romanization suffix across ?123 so tone digits still work.
    self.lastInputWasSymbol = false
    self.page = self.page == .letters ? .numbers : .letters
    self.updateCandidates()
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
