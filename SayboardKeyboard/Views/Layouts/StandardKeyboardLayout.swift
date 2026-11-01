import SwiftUI

/// A single, measured canvas handles both heights. The mic is positioned
/// independently from the fixed key rows so recording can smoothly bring
/// it to the actual vertical center instead of leaving a large empty void.
struct StandardKeyboardLayout: View {
  let proxy: KeyboardProxy
  @ObservedObject var keyboardState: KeyboardState

  private var chrome: KeyboardChromeMetrics {
    KeyboardChromeMetrics(keyboardState: self.keyboardState)
  }

  var body: some View {
    GeometryReader { geometry in
      let compact = KeyboardMetrics.isCompactStandard
      let gap = KeyboardMetrics.rowGap.kbScaled
      let normalMic = MicSizing.standard
      let keyHeight = KeyboardChromeMetrics.keyHeight
      let rowsHeight = compact
        ? 2 * keyHeight + gap
        : normalMic.buttonHeight + 2 * keyHeight + 2 * gap
      let topInset = compact
        ? max(0, (geometry.size.height - rowsHeight) / 2)
        : max(0, geometry.size.height - rowsHeight - 4.kbScaled)
      let restingY = topInset + (compact ? keyHeight / 2 : normalMic.buttonHeight / 2)
      let focused = self.keyboardState.isStartingRecording || self.keyboardState.isRecording
      let mic = compact
        ? MicSizing.compact(spaceBarWidth: self.chrome.spaceBarWidth(totalWidth: geometry.size.width))
        : normalMic

      ZStack(alignment: .top) {
        VStack(spacing: gap) {
          if !compact {
            Color.clear.frame(height: normalMic.buttonHeight)
          }
          self.controlsRow
          KeyboardBottomRow(
            proxy: self.proxy,
            metrics: self.chrome,
            keyboardState: self.keyboardState
          )
        }
        .padding(.top, topInset)
        .frame(maxWidth: .infinity, alignment: .top)

        MicButtonWithPulse(
          sizing: mic,
          proxy: self.proxy,
          reservesPulseSpace: false,
          keyboardState: self.keyboardState
        )
        .position(
          x: geometry.size.width / 2,
          y: focused ? geometry.size.height / 2 : restingY
        )
        .zIndex(1)
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: focused)
        .animation(.easeInOut(duration: 0.20), value: compact)
      }
      .frame(width: geometry.size.width, height: geometry.size.height)
    }
  }

  private var controlsRow: some View {
    GeometryReader { geometry in
      let sideWidth = self.chrome.sideButtonWidth
      let reserved = (sideWidth * 4) + (KeyboardChromeMetrics.buttonSpacing * 6) + 16.kbScaled
      let available = self.keyboardState.auxiliaryControlsHidden
        ? geometry.size.width - 8.kbScaled
        : max(75.kbScaled, geometry.size.width - reserved)

      ZStack(alignment: .center) {
        self.sideButtons
          .padding(.horizontal, 4.kbScaled)
        if !KeyboardMetrics.isCompactStandard {
          KeyboardStatusStrip(keyboardState: self.keyboardState)
            .frame(width: available, height: KeyboardChromeMetrics.keyHeight)
            .allowsHitTesting(false)
        }
      }
    }
    .frame(height: KeyboardChromeMetrics.keyHeight)
  }
}

extension StandardKeyboardLayout {
  private var sideButtons: some View {
    HStack(alignment: .bottom, spacing: KeyboardChromeMetrics.buttonSpacing) {
      KeyButton(
        content: .systemImage("gearshape"),
        fixedWidth: self.chrome.sideButtonWidth,
        fillOnPress: true,
        firesHaptic: false
      ) {
        if let url = DeepLink.settingsURL { self.proxy.openURL(url) }
      }
      TranslateToggleButton(fixedWidth: self.chrome.sideButtonWidth, keyboardState: self.keyboardState)
        .transition(.opacity.combined(with: .scale))
      Spacer(minLength: 0)
      VStack(alignment: .trailing, spacing: 8.5.kbScaled) {
        if self.keyboardState.hasLLMHistory {
          self.undoRedoRow.transition(.opacity.combined(with: .move(edge: .bottom)))
        }
        HStack(spacing: KeyboardChromeMetrics.buttonSpacing) {
          if self.keyboardState.showsAIButton {
            self.aiButton.transition(.opacity.combined(with: .scale))
          } else {
            // Keep the two right-side slots symmetric even without a local LLM.
            Color.clear.frame(width: self.chrome.sideButtonWidth)
          }
          RepeatDeleteButton(proxy: self.proxy, fixedWidth: self.chrome.sideButtonWidth)
        }
      }
    }
    .opacity(self.keyboardState.auxiliaryControlsHidden ? 0 : 1)
    .allowsHitTesting(!self.keyboardState.auxiliaryControlsHidden)
    .animation(.easeOut(duration: 0.22), value: self.keyboardState.auxiliaryControlsHidden)
    .animation(.easeInOut(duration: 0.35), value: self.keyboardState.selectedVariantSupportsTranslation)
    .animation(.easeInOut(duration: 0.35), value: self.keyboardState.showsAIButton)
    .animation(.easeInOut(duration: 0.25), value: self.keyboardState.hasLLMHistory)
  }

  private var undoRedoRow: some View {
    HStack(spacing: KeyboardChromeMetrics.buttonSpacing) {
      KeyButton(
        content: .systemImage("arrow.uturn.backward"),
        fixedWidth: self.chrome.sideButtonWidth,
        firesHaptic: false
      ) {
        self.proxy.undoLLM()
      }
      .disabled(!self.keyboardState.canUndoLLM)
      .opacity(self.keyboardState.canUndoLLM ? 1 : 0.35)

      KeyButton(
        content: .systemImage("arrow.uturn.forward"),
        fixedWidth: self.chrome.sideButtonWidth,
        firesHaptic: false
      ) {
        self.proxy.redoLLM()
      }
      .disabled(!self.keyboardState.canRedoLLM)
      .opacity(self.keyboardState.canRedoLLM ? 1 : 0.35)
    }
  }

  @ViewBuilder
  private var aiButton: some View {
    if self.keyboardState.isLLMProcessing {
      MetaballSpinner(color: .primary, size: 18.kbScaled)
        .frame(width: self.chrome.sideButtonWidth, height: KeyboardChromeMetrics.keyHeight)
        .background {
          RoundedRectangle(cornerRadius: KeyboardChromeMetrics.keyCornerRadius, style: .continuous)
            .fill(Color(.keyBackground))
        }
    } else {
      let isRecording = self.keyboardState.isRecording
      AIButton(
        fixedWidth: self.chrome.sideButtonWidth,
        onTap: { KeyboardActions.tapLLM(state: self.keyboardState, proxy: self.proxy) },
        onLongPress: { KeyboardActions.longPressLLM(state: self.keyboardState, proxy: self.proxy) },
        longPressEnabled: self.keyboardState.longPressLLMAction.isSet,
        isActive: self.keyboardState.showLLMActions
      )
      .opacity(isRecording ? 0.5 : 1)
      .allowsHitTesting(!isRecording)
      .animation(.easeOut(duration: 0.2), value: isRecording)
    }
  }
}
