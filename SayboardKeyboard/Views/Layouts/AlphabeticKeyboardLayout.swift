import SwiftUI

/// English letter typing with a persistent microphone. The keyboard order is
/// QWERTZ by default; users can select QWERTY in Keyboard settings.
/// Uses the existing input proxy, emoji, backspace repeat, spacebar trackpad,
/// and the same on-device dictation pipeline as the other keyboard modes.
struct AlphabeticKeyboardLayout: View {
  let proxy: KeyboardProxy
  @ObservedObject var keyboardState: KeyboardState

  @AppStorage(
    SharedKey.keyboardLetterArrangement,
    store: UserDefaults(suiteName: AppGroup.identifier)
  )
  private var arrangementRaw = LetterKeyArrangement.qwertz.rawValue

  @State private var page = AlphabeticPage.letters
  @State private var shiftActive = true
  @State private var capsLock = false
  @State private var lastShiftTap: Date?

  private var arrangement: LetterKeyArrangement {
    LetterKeyArrangement(rawValue: self.arrangementRaw) ?? .qwertz
  }

  private var chrome: KeyboardChromeMetrics {
    KeyboardChromeMetrics(keyboardState: self.keyboardState)
  }

  private static let rowSpacing: CGFloat = 7.5

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
        onAlphabeticModeSwitch: {
          self.page = self.page == .letters ? .numbers : .letters
        }
      )
    }
    .padding(.top, 3.kbScaled)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }

  private var toolbar: some View {
    HStack(spacing: KeyboardChromeMetrics.buttonSpacing) {
      HStack(spacing: KeyboardChromeMetrics.buttonSpacing) {
        KeyButton(
          content: .systemImage("gearshape"),
          fixedWidth: self.chrome.sideButtonWidth,
          firesHaptic: true
        ) {
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
      }
      .opacity(self.keyboardState.auxiliaryControlsHidden ? 0 : 1)
      .allowsHitTesting(!self.keyboardState.auxiliaryControlsHidden)

      Spacer(minLength: 2.kbScaled)

      if self.keyboardState.hasFullAccess && self.keyboardState.isMicrophoneAuthorized
          && self.keyboardState.hasUsableModel {
        MicButtonWithPulse(
          sizing: .extended(width: 86.kbScaled),
          proxy: self.proxy,
          reservesPulseSpace: false,
          keyboardState: self.keyboardState
        )
      } else {
        KeyButton(
          content: .systemImage("mic.slash"),
          fixedWidth: 86.kbScaled,
          firesHaptic: true
        ) {
          if let url = DeepLink.setupMicURL ?? DeepLink.settingsURL {
            self.proxy.openURL(url)
          }
        }
        .accessibilityLabel("Open Altboard to enable speech recognition")
      }
    }
    .padding(.horizontal, 5.kbScaled)
    .frame(height: 52.kbScaled)
    .animation(.easeOut(duration: 0.22), value: self.keyboardState.auxiliaryControlsHidden)
  }

  @ViewBuilder
  private var firstKeyRow: some View {
    switch self.page {
    case .letters:
      self.letterRow(self.arrangement.rows[0], indent: 0)
    case .numbers:
      self.characterRow(Self.numbersRow1)
    case .symbols:
      self.characterRow(Self.symbolsRow1)
    }
  }

  @ViewBuilder
  private var secondKeyRow: some View {
    switch self.page {
    case .letters:
      self.letterRow(self.arrangement.rows[1], indent: 15.kbScaled)
    case .numbers:
      self.characterRow(Self.numbersRow2)
    case .symbols:
      self.characterRow(Self.symbolsRow2)
    }
  }

  @ViewBuilder
  private var thirdKeyRow: some View {
    switch self.page {
    case .letters:
      HStack(spacing: KeyboardChromeMetrics.buttonSpacing) {
        KeyButton(
          content: .systemImage(self.capsLock ? "capslock.fill"
            : self.shiftActive ? "shift.fill" : "shift"),
          fixedWidth: 48.kbScaled,
          fillOnPress: self.shiftActive || self.capsLock
        ) { self.tapShift() }
        .accessibilityLabel(self.capsLock ? "Caps Lock" : "Shift")

        ForEach(Array(self.arrangement.rows[2].enumerated()), id: \.offset) { index, letter in
          self.letterKey(letter, index: index, count: 7)
        }

        RepeatDeleteButton(proxy: self.proxy, fixedWidth: 48.kbScaled)
      }
      .padding(.horizontal, 4.kbScaled)

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
            self.proxy.insertText(value)
          }
        }
        RepeatDeleteButton(proxy: self.proxy, fixedWidth: 48.kbScaled)
      }
      .padding(.horizontal, 4.kbScaled)
    }
  }

  private func letterRow(_ letters: [String], indent: CGFloat) -> some View {
    HStack(spacing: KeyboardChromeMetrics.buttonSpacing) {
      ForEach(Array(letters.enumerated()), id: \.offset) { index, letter in
        self.letterKey(letter, index: index, count: letters.count)
      }
    }
    .padding(.horizontal, 4.kbScaled + indent)
    .frame(height: KeyboardChromeMetrics.keyHeight)
  }

  private func letterKey(_ letter: String, index: Int, count: Int) -> some View {
    AlphabeticLetterKey(
      letter: letter,
      uppercase: self.shiftActive || self.capsLock,
      column: index,
      rowCount: count
    ) { typed in
      self.proxy.insertText(typed)
      if !self.capsLock { self.shiftActive = false }
      self.lastShiftTap = nil
    }
  }

  private func characterRow(_ characters: [String]) -> some View {
    HStack(spacing: KeyboardChromeMetrics.buttonSpacing) {
      ForEach(characters, id: \.self) { character in
        KeyButton(content: .symbol(character, fontSize: 19), showsCallout: true,
          calloutRowSpacing: Self.rowSpacing.kbScaled) {
          self.proxy.insertText(character)
        }
      }
    }
    .padding(.horizontal, 4.kbScaled)
    .frame(height: KeyboardChromeMetrics.keyHeight)
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
