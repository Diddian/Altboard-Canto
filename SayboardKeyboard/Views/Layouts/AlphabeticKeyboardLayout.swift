import SwiftUI
import UIKit

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
    SharedKey.keyboardAutoCapitalizationEnabled,
    store: UserDefaults(suiteName: AppGroup.identifier)
  )
  private var autoCapitalize = true

  @State private var page = AlphabeticPage.letters
  @State private var lastInputWasSymbol = false
  @State private var shiftActive = true
  @State private var capsLock = false
  @State private var lastShiftTap: Date?
  @AppStorage(
    SharedKey.keyboardChineseInputMode,
    store: UserDefaults(suiteName: AppGroup.identifier)
  )
  private var chineseModeRaw = ChineseInputMode.phonetic.rawValue
  @State private var shapeBuffer = ""
  @State private var shapeCandidates = [ChineseShapeCandidate]()
  @State private var expandedShapeCandidates = [ChineseShapeCandidate]()
  @State private var shapeHostAnchor: String?
  @State private var composition = JyutpingComposition()
  @State private var candidates = [JyutpingCandidate]()
  @State private var candidateLookupSpelling = ""
  @State private var expandedCandidates = [JyutpingCandidate]()
  @State private var showsCandidateGrid = false
  @State private var activeLatinWord: String?
  @State private var latinSuggestions = [LatinWordSuggestion]()
  @State private var swipeAlternatives = [String]()
  @State private var liveSwipePath = [LatinSwipePoint]()
  @State private var nextCantoneseWords = [String]()
  @State private var predictionAnchor: String?
  @State private var nextChineseQuoteCloses = false
  @AppStorage(
    SharedKey.keyboardSwipeTypingEnabled,
    store: UserDefaults(suiteName: AppGroup.identifier)
  )
  private var swipeTypingEnabled = false
  @State private var latinRefreshTask: Task<Void, Never>?
  @State private var cantoneseRefreshTask: Task<Void, Never>?
  @State private var cursorRefreshTask: Task<Void, Never>?
  @State private var isCursorTracking = false
  @AppStorage(
    SharedKey.keyboardTouchDebugOverlay,
    store: UserDefaults(suiteName: AppGroup.identifier)
  )
  private var showTouchDebug = false
  @AppStorage(
    SharedKey.keyboardAdaptiveTouchEnabled,
    store: UserDefaults(suiteName: AppGroup.identifier)
  )
  private var adaptiveTouchEnabled = false

  private var arrangement: LetterKeyArrangement {
    LetterKeyArrangement(rawValue: self.arrangementRaw) ?? .qwertz
  }

  private var offersCantonese: Bool {
    SharedSettings().preferredSpokenLanguages.contains("yue")
  }

  private var offersChineseInput: Bool {
    !InputMethodCatalog.available(
      for: SharedSettings().preferredSpokenLanguages
    ).isEmpty
  }

  private var chineseMode: ChineseInputMode {
    guard self.offersChineseInput else { return .phonetic }
    return ChineseInputMode(rawValue: self.chineseModeRaw) ?? .phonetic
  }

  private var usesShapeMode: Bool {
    self.chineseMode.usesShapeTable && self.page == .letters
  }

  private var shapeDisplay: String {
    self.chineseMode == .stroke
      ? ChineseStrokeKeys.glyphs(for: self.shapeBuffer)
      : self.shapeBuffer.uppercased()
  }

  private var usesChinesePunctuation: Bool {
    !Set(SharedSettings().preferredSpokenLanguages).isDisjoint(with: ["yue", "zh"])
  }

  private var isChineseSymbolsPage: Bool {
    self.page == .symbols && self.usesChinesePunctuation
  }

  private var smartChineseQuote: String {
    self.nextChineseQuoteCloses ? "」" : "「"
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
      Group {
        if self.usesShapeMode && self.chineseMode == .stroke {
          ChineseStrokeGrid(
            onStroke: { self.appendShapeCode($0) },
            onPunctuation: { self.insertShapePunctuation($0) },
            onDelete: { self.deleteShapeStroke() }
          )
        } else {
          // Keep the three-row touch bands under one UIKit touch owner.
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
          .overlay {
            if self.page == .letters && self.swipeTypingEnabled
              && self.chineseMode == .phonetic {
              SwipeTrailOverlay(points: self.liveSwipePath)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
          }
        }
      }
      .frame(height: 3 * KeyboardChromeMetrics.keyHeight
        + 2 * Self.rowSpacing.kbScaled)
      .opacity(self.isCursorTracking ? 0.07 : 1)
      .allowsHitTesting(!self.isCursorTracking)
      .animation(.easeOut(duration: 0.13), value: self.isCursorTracking)

      KeyboardBottomRow(
        proxy: self.proxy,
        metrics: self.chrome,
        keyboardState: self.keyboardState,
        alphabeticModeLabel: self.page == .letters ? "?123" : "ABC",
        onAlphabeticModeSwitch: { self.toggleNumberPage() },
        showsAlphabetIndicator: self.page == .letters,
        onSpaceAction: { self.handleSpace() },
        onReturnAction: { self.handleReturn() },
        onCursorTrackingBegan: { self.beginCursorTracking() },
        onCursorTrackingEnded: { self.endCursorTracking() }
      )
      .padding(.top, Self.rowSpacing.kbScaled)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .overlay(alignment: .top) {
      if self.showsCandidateGrid,
         (!self.expandedCandidates.isEmpty || !self.expandedShapeCandidates.isEmpty),
         self.page == .letters {
        Group {
          if self.usesShapeMode {
            self.expandedShapeCandidateGrid
          } else {
            self.expandedCandidateGrid
          }
        }
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
    .onChange(of: self.chineseModeRaw) { _, _ in
      self.clearComposition()
      self.clearShapeComposition()
      self.liveSwipePath.removeAll()
      self.updateCandidates()
    }
    .onChange(of: self.autoCapitalize) { _, _ in self.refreshAutomaticShift() }
    .onChange(of: self.keyboardState.textContextRevision) { _, _ in
      if !self.swipeAlternatives.isEmpty {
        let prefix = self.swipeAlternatives[0] + " "
        if self.proxy.documentContextBeforeInput()?.hasSuffix(prefix) != true {
          self.swipeAlternatives.removeAll()
        }
      }
      // Never let a pre-edit span follow the user into a different host field.
      if !self.shapeBuffer.isEmpty &&
         self.shapeHostAnchor != self.proxy.documentContextBeforeInput() {
        self.clearShapeComposition()
      }
      if !self.composition.isEmpty && !self.trackedTextMatches {
        self.clearComposition()
      }
      self.refreshAutomaticShift()
      self.updateCandidates()
    }
    .onDisappear {
      self.clearShapeComposition()
      self.liveSwipePath.removeAll()
      self.latinRefreshTask?.cancel()
      self.cursorRefreshTask?.cancel()
      self.activeLatinWord = nil
      self.swipeAlternatives.removeAll()
      self.latinSuggestions.removeAll()
      self.composition.clear()
      self.candidates.removeAll()
      self.expandedCandidates.removeAll()
      self.candidateLookupSpelling = ""
      self.showsCandidateGrid = false
    }
  }

  private var toolbar: some View {
    HStack(spacing: KeyboardChromeMetrics.buttonSpacing) {
      if self.keyboardState.showLLMActions {
        KeyboardLLMActionsToolbar(proxy: self.proxy, keyboardState: self.keyboardState)
      } else if self.page == .letters && !self.swipeAlternatives.isEmpty {
        self.swipeCandidateStrip
      } else if self.page == .letters && !self.nextCantoneseWords.isEmpty {
        self.nextCantoneseCandidateStrip
      } else if self.page == .letters &&
          ((self.offersCantonese && !self.composition.isEmpty)
            || (self.usesShapeMode && !self.shapeBuffer.isEmpty)
            || self.activeLatinWord != nil) {
        // The full toolbar becomes an iOS-style prediction strip for the
        // currently typed word, in Cantonese, German, English or another
        // available preferred spellchecker language. Hide mic and controls.
        self.candidateStrip
        if (self.offersCantonese && !self.composition.isEmpty)
          || (self.usesShapeMode && !self.shapeBuffer.isEmpty) {
          Button {
            self.showsCandidateGrid.toggle()
            if self.showsCandidateGrid {
              if self.usesShapeMode {
                self.expandedShapeCandidates = ChineseShapeDictionary.shared.candidates(
                  for: self.shapeBuffer, mode: self.chineseMode, limit: 200
                )
              } else {
                self.expandedCandidates = JyutpingDictionary.shared.candidates(
                  for: self.composition.buffer, limit: 200
                )
              }
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

        if self.offersChineseInput {
          KeyButton(
            content: .symbol(self.chineseMode.shortTitle, fontSize: 20),
            fixedWidth: self.chrome.sideButtonWidth
          ) {
            self.cycleChineseMode()
          }
          .accessibilityLabel("中文輸入：\(self.chineseMode.title)，點按切換")
          .accessibilityHint("拼音、速成、倉頡、筆劃")
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
        if self.keyboardState.isRecording {
          LongRecordingNotice(startedAt: self.keyboardState.recordingStartedAt)
        }
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
    .transaction { $0.animation = nil }
  }

  private var swipeCandidateStrip: some View {
    GeometryReader { geometry in
      let width = geometry.size.width / 3
      HStack(spacing: 0) {
        ForEach(Array(self.swipeAlternatives.prefix(3).enumerated()), id: \.offset) { index, value in
          self.suggestionCell(
            value, width: width, showDivider: index < 2
          ) {
            self.acceptSwipeAlternative(value)
          }
        }
      }
    }
    .frame(height: KeyboardChromeMetrics.keyHeight)
  }

  private func acceptSwipeAlternative(_ value: String) {
    guard let current = self.swipeAlternatives.first,
          let host = self.proxy.documentContextBeforeInput(),
          host.hasSuffix(current + " ") else {
      self.swipeAlternatives.removeAll()
      return
    }
    for _ in 0..<(current.count + 1) { self.proxy.deleteBackward() }
    self.proxy.insertText(value + " ")
    self.swipeAlternatives.removeAll()
    self.refreshAutomaticShift()
    self.updateCandidates()
  }

  private func commitSwipe(_ alternatives: [String]) {
    guard !alternatives.isEmpty else { return }
    let shouldCapitalize = self.shiftActive || self.capsLock
    let adjusted = alternatives.map { word in
      shouldCapitalize ? word.prefix(1).uppercased() + word.dropFirst() : word
    }
    guard let chosen = adjusted.first else { return }
    self.clearComposition()
    self.swipeAlternatives = adjusted
    let separator = LatinWordSuggestionPolicy.swipeLeadingSeparator(
      in: self.proxy.documentContextBeforeInput()
    )
    self.proxy.insertText(separator + chosen + " ")
    self.lastShiftTap = nil
    if !self.capsLock { self.shiftActive = false }
    self.updateCandidates()
  }

  private var nextCantoneseCandidateStrip: some View {
    GeometryReader { geometry in
      ScrollView(.horizontal) {
        HStack(spacing: 0) {
          ForEach(Array(self.nextCantoneseWords.enumerated()), id: \.offset) { index, word in
            self.suggestionCell(
              word, width: geometry.size.width / 3, showDivider: index % 3 != 2
            ) {
              self.chooseContinuation(word)
            }
          }
        }
      }
      .scrollIndicators(.hidden)
    }
    .frame(height: KeyboardChromeMetrics.keyHeight)
  }

  private func chooseContinuation(_ text: String) {
    guard let anchor = self.predictionAnchor,
          self.proxy.documentContextBeforeInput()?.hasSuffix(anchor) == true else {
      self.nextCantoneseWords.removeAll()
      self.predictionAnchor = nil
      return
    }
    self.proxy.insertText(text)
    self.predictionAnchor = text
    self.nextCantoneseWords = JyutpingDictionary.shared.continuations(after: text)
    self.updateCandidates()
  }

  private var currentLiteral: String {
    if self.usesShapeMode && !self.shapeBuffer.isEmpty { return self.shapeDisplay }
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
      // Keep Latin fallbacks out of a pending or populated Cantonese row.
      // They remain available once the current spelling has no Canto hits.
      let prioritizesChinese = self.offersCantonese && !self.composition.isEmpty
        && (self.candidateLookupSpelling != self.composition.buffer
          || !self.candidates.isEmpty)
      let corrected = self.usesShapeMode || prioritizesChinese ? nil
        : EnglishCaseSuggestion.replacement(for: self.currentLiteral)
      let firstCantoneseSlot = corrected == nil ? 1 : 2

      ScrollView(.horizontal) {
        HStack(spacing: 0) {
          self.suggestionCell(self.currentLiteral, width: width, showDivider: true) {
            if self.usesShapeMode {
              self.insertShapeLiteral()
            } else {
              self.latinRefreshTask?.cancel()
              self.activeLatinWord = nil
              self.latinSuggestions.removeAll()
              self.clearComposition()
              KeyboardInputTrace.record(.latinKept)
            }
          }

          if let corrected {
            self.suggestionCell(corrected, width: width, showDivider: true) {
              self.chooseLatinSuggestion(corrected)
            }
          }

          ForEach(Array(self.shapeCandidates.enumerated()), id: \.offset) { index, candidate in
            self.suggestionCell(
              candidate.text, width: width, showDivider: (firstCantoneseSlot + index) % 3 != 2
            ) {
              self.chooseShape(candidate)
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

          if !prioritizesChinese {
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
      }
      .scrollIndicators(.hidden)
    }
    .frame(height: KeyboardChromeMetrics.keyHeight)
  }

  private var expandedShapeCandidateGrid: some View {
    ScrollView(.vertical) {
      LazyVGrid(
        columns: Array(repeating: GridItem(.flexible(), spacing: 3.kbScaled), count: 4),
        spacing: 3.kbScaled
      ) {
        ForEach(self.expandedShapeCandidates) { candidate in
          Button {
            KeyboardHaptics.key()
            self.chooseShape(candidate)
          } label: {
            Text(verbatim: candidate.text)
              .font(.system(size: 20.kbScaled))
              .foregroundStyle(.primary)
              .lineLimit(1)
              .minimumScaleFactor(0.7)
              .frame(maxWidth: .infinity, minHeight: 39.kbScaled)
              .background(
                Color(uiColor: KeyboardPalette.keyFill),
                in: RoundedRectangle(cornerRadius: 6.kbScaled)
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
      in: RoundedRectangle(cornerRadius: 9.kbScaled)
    )
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
                     top: 0, bottom: Self.rowSpacing / 2, rowIndex: 0)
    case .numbers: self.characterRow(Self.numbersRow1)
    case .symbols: self.characterRow(self.isChineseSymbolsPage ? Self.chineseSymbolsRow1 : Self.symbolsRow1)
    }
  }

  @ViewBuilder
  private var secondKeyRow: some View {
    switch self.page {
    case .letters:
      self.letterRow(self.arrangement.rows[1], inset: Self.secondInset,
                     top: Self.rowSpacing / 2, bottom: Self.rowSpacing / 2, rowIndex: 1)
    case .numbers: self.characterRow(Self.numbersRow2)
    case .symbols: self.characterRow(self.isChineseSymbolsPage ? Self.chineseSymbolsRow2 : Self.symbolsRow2)
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
                       top: Self.rowSpacing / 2, bottom: 0, rowIndex: 2)
        RepeatDeleteButton(
          proxy: self.proxy,
          fixedWidth: 50.kbScaled,
          onDeleteIntercept: { self.deleteCompositionCharacter() },
          onTapDeleteIntercept: { self.interceptAlphabeticDelete() },
          onHostDeletion: { self.handleHostDeletion() },
          fastCompositionRepeat: self.offersCantonese && !self.composition.isEmpty
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
            ForEach(0..<5, id: \.self) { index in
              let value = self.isChineseSymbolsPage
                ? ["。", "，", "？", "！", self.smartChineseQuote][index]
                : [".", ",", "?", "!", "'"][index]
              KeyButton(
                content: .symbol(self.nativeSymbolFace(value), fontSize: 18),
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
            onHostDeletion: { self.handleHostDeletion() },
          fastCompositionRepeat: self.offersCantonese && !self.composition.isEmpty
          )
        }
        .padding(.horizontal, inset)
      }
      .frame(height: KeyboardChromeMetrics.keyHeight)
    }
  }

  private var touchPredictionPrefix: String? {
    if self.usesShapeMode { return nil }
    if self.offersCantonese && !self.composition.isEmpty {
      // Candidate pronunciations use canonical Jyutping, but the live input
      // may mix Jyutping, Yale and Sidney Lau. Neutral hit cells are safer
      // than predicting the next key using a mismatched romanization.
      return nil
    }
    return self.activeLatinWord
  }

  private var touchPredictionWords: [String] {
    if self.usesShapeMode { return [] }
    if self.offersCantonese && !self.composition.isEmpty {
      return []
    }
    return self.latinSuggestions.map(\.text)
  }

  private func letterRow(
    _ letters: [String], inset: CGFloat, top: CGFloat, bottom: CGFloat,
    rowIndex: Int
  ) -> some View {
    AlphabeticTouchRow(
      letters: letters,
      uppercase: self.shiftActive || self.capsLock,
      horizontalInset: inset.kbScaled,
      topHitInset: top.kbScaled,
      bottomHitInset: bottom.kbScaled,
      typedContext: self.touchPredictionPrefix,
      completionWords: self.touchPredictionWords,
      showTouchDebug: self.showTouchDebug,
      adaptiveTouchEnabled: self.adaptiveTouchEnabled,
      swipeEnabled: self.swipeTypingEnabled && self.chineseMode == .phonetic,
      swipeArrangement: self.arrangement,
      swipeRowIndex: rowIndex,
      chineseInputMode: self.chineseMode,
      onSwipe: { words in self.commitSwipe(words) },
      onSwipePath: { path in self.liveSwipePath = path }
    ) { typed in
      self.handleCharacter(typed)
      self.lastShiftTap = nil
    }
  }

  private func characterRow(_ characters: [String]) -> some View {
    HStack(spacing: KeyboardChromeMetrics.buttonSpacing) {
      ForEach(characters, id: \.self) { character in
        KeyButton(content: .symbol(self.nativeSymbolFace(character), fontSize: 18),
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
    if self.usesShapeMode,
       character.count == 1, character.allSatisfy({ $0.isASCII && $0.isLetter }) {
      self.appendShapeCode(character.lowercased())
      return
    }
    if self.usesShapeMode && !self.shapeBuffer.isEmpty {
      if let first = self.shapeCandidates.first { self.chooseShape(first) }
      else { self.clearShapeComposition() }
    }
    self.swipeAlternatives.removeAll()
    self.nextCantoneseWords.removeAll()
    self.predictionAnchor = nil
    if self.usesChinesePunctuation {
      if character == "「" || character == "『" { self.nextChineseQuoteCloses = true }
      if character == "」" || character == "』" { self.nextChineseQuoteCloses = false }
    }
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
    guard !self.isCursorTracking else { return }
    self.cantoneseRefreshTask?.cancel()
    if self.usesShapeMode {
      self.candidates.removeAll()
      self.expandedCandidates.removeAll()
      self.latinRefreshTask?.cancel()
      self.latinSuggestions.removeAll()
      self.activeLatinWord = nil
      self.shapeCandidates = self.shapeBuffer.isEmpty ? []
        : ChineseShapeDictionary.shared.candidates(
            for: self.shapeBuffer, mode: self.chineseMode
          )
      if self.showsCandidateGrid && !self.shapeBuffer.isEmpty {
        self.expandedShapeCandidates = ChineseShapeDictionary.shared.candidates(
          for: self.shapeBuffer, mode: self.chineseMode, limit: 200
        )
      } else {
        self.expandedShapeCandidates.removeAll()
      }
      return
    }
    self.shapeCandidates.removeAll()
    self.expandedShapeCandidates.removeAll()
    if self.offersCantonese && !self.composition.isEmpty {
      let prefix = self.composition.buffer
      // Do not empty the visible row during the 24 ms debounce. The previous
      // candidates stay visible until the matching lookup is ready, but are
      // never selectable for a different spelling.
      self.cantoneseRefreshTask = Task { @MainActor in
        do { try await Task.sleep(for: .milliseconds(24)) } catch { return }
        guard !Task.isCancelled, !self.isCursorTracking,
              self.composition.buffer == prefix else { return }
        let newCandidates = JyutpingDictionary.shared.candidates(for: prefix)
        guard !Task.isCancelled, self.composition.buffer == prefix else { return }
        let expanded = self.showsCandidateGrid && !newCandidates.isEmpty
          ? JyutpingDictionary.shared.candidates(for: prefix, limit: 200) : []
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
          if self.candidates != newCandidates { self.candidates = newCandidates }
          self.candidateLookupSpelling = prefix
          if self.expandedCandidates != expanded { self.expandedCandidates = expanded }
        }
      }
    } else {
      if !self.candidates.isEmpty { self.candidates.removeAll() }
      if !self.expandedCandidates.isEmpty { self.expandedCandidates.removeAll() }
      self.candidateLookupSpelling = ""
    }

    let typed = self.page == .letters
      ? LatinWordSuggestionPolicy.trailingWord(in: self.proxy.documentContextBeforeInput())
      : nil
    self.activeLatinWord = typed
    self.latinRefreshTask?.cancel()
    guard let typed else {
      self.latinSuggestions.removeAll()
      return
    }
    // Keep stable suggestions on-screen between asynchronous dictionary lookups.
    let preferred = SharedSettings().preferredSpokenLanguages
    let immediate = LatinWordSuggestions.shared.fastChoices(for: typed, preferred: preferred)
    if self.latinSuggestions != immediate { self.latinSuggestions = immediate }

    // Let key-down animation render before asking the installed OS
    // spellchecker for suggestions. Drop stale work during fast typing.
    self.latinRefreshTask = Task { @MainActor in
      do { try await Task.sleep(for: .milliseconds(45)) } catch { return }
      guard !Task.isCancelled,
            self.activeLatinWord == typed,
            LatinWordSuggestionPolicy.trailingWord(
              in: self.proxy.documentContextBeforeInput()
            ) == typed else { return }
      let values = LatinWordSuggestions.shared.choices(for: typed, preferred: preferred)
      guard !Task.isCancelled, self.activeLatinWord == typed else { return }
      if values != self.latinSuggestions {
        var noAnimation = Transaction(animation: nil)
        noAnimation.disablesAnimations = true
        withTransaction(noAnimation) { self.latinSuggestions = values }
      }
    }
  }

  private func beginCursorTracking() {
    self.clearShapeComposition()
    self.swipeAlternatives.removeAll()
    self.cursorRefreshTask?.cancel()
    self.latinRefreshTask?.cancel()
    self.cantoneseRefreshTask?.cancel()
    self.isCursorTracking = true
    self.liveSwipePath = []
    self.activeLatinWord = nil
    self.latinSuggestions.removeAll()
    self.candidates.removeAll()
    self.expandedCandidates.removeAll()
    self.candidateLookupSpelling = ""
    self.showsCandidateGrid = false
  }

  private func endCursorTracking() {
    self.isCursorTracking = false
    self.cursorRefreshTask?.cancel()
    self.cursorRefreshTask = Task { @MainActor in
      do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
      guard !Task.isCancelled, !self.isCursorTracking else { return }
      if !self.composition.isEmpty && !self.trackedTextMatches {
        self.clearComposition()
      }
      self.refreshAutomaticShift()
      self.updateCandidates()
    }
  }

  private func clearComposition() {
    self.composition.clear()
    self.cantoneseRefreshTask?.cancel()
    self.candidates.removeAll()
    self.expandedCandidates.removeAll()
    self.candidateLookupSpelling = ""
    self.showsCandidateGrid = false
  }

  /// Delete the *last syllable* of a verified complete Cantonese spelling.
  /// gamyat → gam (remove yat), not an entire "gamyat" word. Unknown English
  /// remains normal character-by-character deletion via RepeatDeleteButton.
  /// Delete a verified last swiped word and its separator on one tap.
  /// Ordinary keystrokes continue to delete one character.
  private func interceptAlphabeticDelete() -> Bool {
    if self.usesShapeMode && !self.shapeBuffer.isEmpty {
      self.shapeBuffer.removeLast()
      self.updateCandidates()
      return true
    }
    if let word = self.swipeAlternatives.first,
       self.proxy.documentContextBeforeInput()?.hasSuffix(word + " ") == true {
      self.swipeAlternatives.removeAll()
      for _ in 0..<(word.count + 1) { self.proxy.deleteBackward() }
      self.updateCandidates()
      self.refreshAutomaticShift()
      return true
    }
    self.swipeAlternatives.removeAll()
    return false
  }

  private func deleteCompositionCharacter() -> Bool {
    if self.usesShapeMode && !self.shapeBuffer.isEmpty {
      self.shapeBuffer.removeLast()
      self.updateCandidates()
      return true
    }
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
    self.nextCantoneseWords.removeAll()
    self.predictionAnchor = nil
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
    // The prior row stays visible during debounce, but must not commit a
    // candidate belonging to the previous spelling.
    guard self.candidateLookupSpelling == self.composition.buffer else { return }
    guard self.trackedTextMatches else {
      self.clearComposition()
      return
    }
    let typedSpelling = self.composition.buffer
    let count = typedSpelling.count
    self.clearComposition()
    for _ in 0..<count { self.proxy.deleteBackward() }
    self.proxy.insertText(candidate.text)
    self.predictionAnchor = candidate.text
    self.nextCantoneseWords = JyutpingDictionary.shared.continuations(after: candidate.text)
    KeyboardInputTrace.record(.candidateChosen)
    JyutpingDictionary.shared.remember(candidate, typed: typedSpelling)
    self.refreshAutomaticShift()
    self.updateCandidates()
  }


  /// Input-method selection is independent from pronunciation schemes. Both
  /// Cangjie generations and both Quick generations are searched together.
  private func cycleChineseMode() {
    let next = self.chineseMode.next
    self.clearComposition()
    self.clearShapeComposition()
    self.nextCantoneseWords.removeAll()
    self.swipeAlternatives.removeAll()
    self.page = .letters
    self.chineseModeRaw = next.rawValue
    self.updateCandidates()
  }

  private func appendShapeCode(_ raw: String) {
    guard self.usesShapeMode else { return }
    let code = raw.lowercased()
    let allowed = self.chineseMode == .stroke ? "nm,./"
      : "abcdefghijklmnopqrstuvwxyz"
    let maximum = self.chineseMode == .quick ? 2
      : self.chineseMode == .stroke ? 64 : 6
    guard code.count == 1, code.allSatisfy({ allowed.contains($0) }) else { return }
    if self.shapeBuffer.count >= maximum {
      // A long Rime stroke sequence must never silently choose the first word.
      if self.chineseMode == .stroke { return }
      if let first = self.shapeCandidates.first { self.chooseShape(first) }
      else { self.insertShapeLiteral() }
    }
    if self.shapeBuffer.isEmpty {
      self.shapeHostAnchor = self.proxy.documentContextBeforeInput()
    }
    self.shapeBuffer += code
    self.nextCantoneseWords.removeAll()
    self.swipeAlternatives.removeAll()
    self.lastShiftTap = nil
    self.shiftActive = false
    self.updateCandidates()
  }

  private func deleteShapeStroke() {
    if self.shapeBuffer.isEmpty {
      self.proxy.deleteBackward()
    } else {
      self.shapeBuffer.removeLast()
      self.updateCandidates()
    }
  }

  private func clearShapeComposition() {
    self.shapeBuffer = ""
    self.shapeHostAnchor = nil
    self.shapeCandidates.removeAll()
    self.expandedShapeCandidates.removeAll()
    self.showsCandidateGrid = false
  }

  private func insertShapeLiteral() {
    guard !self.shapeBuffer.isEmpty else { return }
    let text = self.shapeBuffer
    self.clearShapeComposition()
    self.proxy.insertText(text)
    self.updateCandidates()
  }

  private func insertShapePunctuation(_ symbol: String) {
    if !self.shapeBuffer.isEmpty {
      if let first = self.shapeCandidates.first { self.chooseShape(first) }
      else { self.clearShapeComposition() }
    }
    self.handleCharacter(symbol)
  }

  private func chooseShape(_ candidate: ChineseShapeCandidate) {
    guard self.usesShapeMode, !self.shapeBuffer.isEmpty,
          candidate.mode == self.chineseMode else { return }
    // A host field switch invalidates the pending code before any commit.
    guard self.shapeHostAnchor == self.proxy.documentContextBeforeInput() else {
      self.clearShapeComposition()
      return
    }
    let typedCode = self.shapeBuffer
    self.clearShapeComposition()
    self.proxy.insertText(candidate.text)
    ChineseShapeDictionary.shared.remember(candidate, typedCode: typedCode)
    self.predictionAnchor = candidate.text
    self.nextCantoneseWords = self.offersCantonese
      ? JyutpingDictionary.shared.continuations(after: candidate.text) : []
    KeyboardInputTrace.record(.candidateChosen)
    self.refreshAutomaticShift()
    self.updateCandidates()
  }

  private func handleSpace() {
    if self.usesShapeMode && !self.shapeBuffer.isEmpty {
      if let first = self.shapeCandidates.first { self.chooseShape(first) }
      else { self.insertShapeLiteral() }
      return
    }
    self.swipeAlternatives.removeAll()
    self.nextCantoneseWords.removeAll()
    self.predictionAnchor = nil
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
    if self.usesShapeMode && !self.shapeBuffer.isEmpty {
      if let first = self.shapeCandidates.first { self.chooseShape(first) }
      else { self.insertShapeLiteral() }
    }
    self.swipeAlternatives.removeAll()
    self.nextCantoneseWords.removeAll()
    self.predictionAnchor = nil
    self.lastInputWasSymbol = false
    self.clearComposition()
    self.proxy.insertText("\n")
    self.refreshAutomaticShift()
    self.updateCandidates()
  }

  private func toggleNumberPage() {
    if self.usesShapeMode && !self.shapeBuffer.isEmpty {
      if let first = self.shapeCandidates.first { self.chooseShape(first) }
      else { self.clearShapeComposition() }
    }
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

  // The #+= page is the ONLY place Chinese punctuation replaces Latin keys.
  // Keep the top rows disjoint from the bottom 。 ， ？ ！ and paired 「/」 key.
  private static let chineseSymbolsRow1 = ["〈","〉","〖","〗","〔","〕","【","】","《","》"]
  private static let chineseSymbolsRow2 = ["『","』","﹏","～","…","、","€","£","¥","•"]

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


/// Persistent UIKit painting surface, separate from the sole UIKit touch
/// owner. SwiftUI Canvas was sometimes not redrawn after repeated host edits.
private struct SwipeTrailOverlay: UIViewRepresentable {
  let points: [LatinSwipePoint]

  func makeUIView(context: Context) -> SwipeTrailDrawingView {
    let view = SwipeTrailDrawingView(frame: .zero)
    view.backgroundColor = .clear
    view.isOpaque = false
    view.isUserInteractionEnabled = false
    return view
  }

  func updateUIView(_ view: SwipeTrailDrawingView, context: Context) {
    view.setPoints(self.points)
  }
}

private final class SwipeTrailDrawingView: UIView {
  private var points = [LatinSwipePoint]()

  func setPoints(_ next: [LatinSwipePoint]) {
    guard self.points != next else { return }
    self.points = next
    self.setNeedsDisplay()
  }

  override func draw(_ rect: CGRect) {
    guard self.points.count > 1, let context = UIGraphicsGetCurrentContext() else { return }
    context.setLineCap(.round)
    context.setLineJoin(.round)
    let last = Double(self.points.count - 1)
    for i in 1..<self.points.count {
      let progress = Double(i) / last
      let a = self.points[i - 1]
      let b = self.points[i]
      context.setLineWidth(CGFloat(8 * (1 - progress) + 1.6))
      context.setStrokeColor(UIColor.label.withAlphaComponent(CGFloat(0.26 * (1 - 0.25 * progress))).cgColor)
      context.beginPath()
      context.move(to: CGPoint(x: a.x, y: a.y))
      context.addLine(to: CGPoint(x: b.x, y: b.y))
      context.strokePath()
    }
  }
}
