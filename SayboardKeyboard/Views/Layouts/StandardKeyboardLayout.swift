import SwiftUI

struct StandardKeyboardLayout: View {
  let proxy: KeyboardProxy
  @ObservedObject var keyboardState: KeyboardState

  var body: some View {
    VStack(spacing: 6.kbScaled) {
      self.micRow
      self.controlsRow
      KeyboardBottomRow(proxy: self.proxy, metrics: self.chrome, keyboardState: self.keyboardState)
    }
  }

  private var chrome: KeyboardChromeMetrics {
    KeyboardChromeMetrics(keyboardState: self.keyboardState)
  }

  private var micRow: some View {
    HStack {
      Spacer(minLength: 0)
      MicButtonWithPulse(
        sizing: .standard,
        proxy: self.proxy,
        reservesPulseSpace: false,
        keyboardState: self.keyboardState
      )
      Spacer(minLength: 0)
    }
    .frame(height: MicSizing.standard.buttonHeight)
  }

  /// Reserves one fixed-height row for four controls and the center status.
  /// During processing the buttons fade and the status uses the full width.
  private var controlsRow: some View {
    GeometryReader { geometry in
      let side = self.chrome.sideButtonWidth
      let reserved = (side * 4) + (KeyboardChromeMetrics.buttonSpacing * 6) + 16.kbScaled
      let available = self.keyboardState.auxiliaryControlsHidden
        ? geometry.size.width - 8.kbScaled
        : max(90.kbScaled, geometry.size.width - reserved)
      ZStack(alignment: .bottom) {
        self.sideButtons
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
        firesHaptic: false,
      ) {
        if let url = DeepLink.settingsURL { self.proxy.openURL(url) }
      }
      TranslateToggleButton(fixedWidth: self.chrome.sideButtonWidth, keyboardState: self.keyboardState)
        .transition(.opacity.combined(with: .scale))
      Spacer()
      VStack(alignment: .trailing, spacing: 8.5.kbScaled) {
        if self.keyboardState.hasLLMHistory {
          self.undoRedoRow
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
        HStack(spacing: KeyboardChromeMetrics.buttonSpacing) {
          if self.keyboardState.showsAIButton {
            self.aiButton.transition(.opacity.combined(with: .scale))
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
        firesHaptic: false,
      ) {
        self.proxy.undoLLM()
      }
      .disabled(!self.keyboardState.canUndoLLM)
      .opacity(self.keyboardState.canUndoLLM ? 1 : 0.35)

      KeyButton(
        content: .systemImage("arrow.uturn.forward"),
        fixedWidth: self.chrome.sideButtonWidth,
        firesHaptic: false,
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
        .frame(width: self.chrome.sideButtonWidth, height: 45.kbScaled)
        .background {
          RoundedRectangle(cornerRadius: 8.5.kbScaled, style: .continuous)
            .fill(Color(.keyBackground))
        }
    } else {
      let isRecording = self.keyboardState.isRecording
      AIButton(
        fixedWidth: self.chrome.sideButtonWidth,
        onTap: { KeyboardActions.tapLLM(state: self.keyboardState, proxy: self.proxy) },
        onLongPress: { KeyboardActions.longPressLLM(state: self.keyboardState, proxy: self.proxy) },
        longPressEnabled: self.keyboardState.longPressLLMAction.isSet,
        isActive: self.keyboardState.showLLMActions,
      )
      .opacity(isRecording ? 0.5 : 1)
      .allowsHitTesting(!isRecording)
      .animation(.easeOut(duration: 0.2), value: isRecording)
    }
  }
}
