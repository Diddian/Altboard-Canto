import SwiftUI

extension KeyboardState {
  var showsAIButton: Bool {
    self.showAIButton && self.llmEnabled && self.hasUsableLLMModel
  }

}

struct KeyboardChromeMetrics {

  @MainActor
  init(keyboardState: KeyboardState) {
    let compact = (keyboardState.showOutputLanguageButton && keyboardState.selectedVariantSupportsTranslation) || keyboardState.showsAIButton
    let side: CGFloat = (keyboardState.effectiveTypingKind == .alphabetic ? 48 : (compact ? 43 : 45)).kbScaled
    let wide: CGFloat = 92.kbScaled
    let showsGlobe = true // Reserve the required system keyboard-switch key.

    self.sideButtonWidth = side
    self.showsGlobe = showsGlobe
    self.trashWidth = showsGlobe ? side : wide
    self.returnWidth = keyboardState.effectiveTypingKind == .alphabetic
      ? 102.kbScaled : (showsGlobe ? (side + Self.buttonSpacing + side) : wide)
  }

  @MainActor
  static var buttonSpacing: CGFloat {
    6.kbScaled
  }

  @MainActor
  static var keyHeight: CGFloat {
    45.kbScaled
  }

  @MainActor
  static var keyCornerRadius: CGFloat {
    8.5.kbScaled
  }

  let sideButtonWidth: CGFloat
  let trashWidth: CGFloat
  let returnWidth: CGFloat
  let showsGlobe: Bool

  /// Exactly the width of SpaceBarKey in KeyboardBottomRow.
  @MainActor
  func spaceBarWidth(totalWidth: CGFloat) -> CGFloat {
    max(
      44.kbScaled,
      totalWidth - self.sideButtonWidth - self.trashWidth - self.returnWidth
        - 3 * Self.buttonSpacing - 8.kbScaled
    )
  }
}

/// Centered status in the existing control row; no extra keyboard height.
struct KeyboardStatusStrip: View {
  @ObservedObject var keyboardState: KeyboardState
  var compact = false

  var body: some View {
    Group {
      if self.keyboardState.isProcessing {
        VoiceProcessingStatusView(
          progress: self.keyboardState.voiceProcessingProgress, compact: self.compact
        )
      } else if self.keyboardState.isStartingRecording && !self.keyboardState.isRecording {
        Text(self.compact ? "Activating…" : "Activating microphone…")
          .font(.caption2.weight(.medium))
          .foregroundStyle(.secondary)
      } else if let outcome = self.keyboardState.dictationOutcome {
        DictationOutcomeLabel(outcome: outcome) {
          self.keyboardState.dictationOutcome = nil
        }
      } else if let preview = self.keyboardState.finalOutputPreview {
        Text(preview)
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(self.compact ? 1 : 2)
          .truncationMode(.tail)
          .accessibilityLabel("Inserted dictation: \(preview)")
      } else if self.keyboardState.isDictationLocked {
        Text("Dictation locked").font(.caption2).foregroundStyle(.secondary)
      }
    }
    .multilineTextAlignment(.center)
    .minimumScaleFactor(0.75)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    .animation(.easeOut(duration: 0.18), value: self.keyboardState.isProcessing)
    .animation(.easeOut(duration: 0.18), value: self.keyboardState.finalOutputPreview)
  }
}

private struct VoiceProcessingStatusView: View {
  let progress: VoiceProcessingProgress?
  var compact = false

  var body: some View {
    VStack(alignment: .center, spacing: 2) {
      HStack(spacing: 5) {
        ProgressView().controlSize(.mini)
        TimelineView(.periodic(from: .now, by: 1)) { context in
          let elapsed = max(0, Int(context.date.timeIntervalSinceReferenceDate
            - (self.progress?.startedAt ?? context.date.timeIntervalSinceReferenceDate)))
          Text("\(self.stageTitle) · \(elapsed)s")
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
      if !self.compact, let raw = self.progress?.rawPreview, !raw.isEmpty {
        Text("Raw: \(raw)")
          .font(.caption2)
          .foregroundStyle(.tertiary)
          .lineLimit(1)
          .truncationMode(.tail)
      }
    }
    .frame(maxWidth: .infinity, alignment: .center)
    .accessibilityElement(children: .combine)
  }

  private var stageTitle: String {
    guard let progress else { return "Processing" }
    switch progress.stage {
    case .stoppingAudio: return "Preparing audio"
    case .loadingRecognizer: return "Loading model"
    case .transcribing: return "Transcribing"
    case .translating: return "Translating"
    case .editing: return "Cleaning up"
    case .finalizing: return "Finalizing"
    }
  }
}

struct KeyboardBottomRow: View {

  let proxy: KeyboardProxy
  let metrics: KeyboardChromeMetrics

  @ObservedObject var keyboardState: KeyboardState
  var alphabeticModeLabel: String? = nil
  var onAlphabeticModeSwitch: (() -> Void)? = nil
  var showsAlphabetIndicator = true
  var onSpaceAction: (() -> Void)? = nil
  var onShortcutAction: ((String) -> Void)? = nil
  var onReturnAction: (() -> Void)? = nil
  var onTextEdited: (() -> Void)? = nil
  var onCursorTrackingBegan: (() -> Void)? = nil
  var onCursorTrackingEnded: (() -> Void)? = nil

  var body: some View {
    GeometryReader { geometry in
      let traits = self.keyboardState.hostInputTraits
      let requested = self.keyboardState.effectiveTypingKind == .standard
        ? [] : traits.bottomShortcuts
      let shortcuts = self.visibleShortcuts(requested, totalWidth: geometry.size.width)
      let returnWidth = shortcuts.isEmpty ? self.metrics.returnWidth : 78.kbScaled
      HStack(spacing: KeyboardChromeMetrics.buttonSpacing) {
      if let action = self.onAlphabeticModeSwitch {
        KeyButton(
          content: .symbol(self.alphabeticModeLabel ?? "?123", fontSize: 16),
          fixedWidth: self.metrics.trashWidth
        ) {
          action()
        }
      }
      // UIKit owns the native input-mode menu, including Apple's Emoji keyboard.
      NativeInputModeSwitchKey(
        configure: self.keyboardState.configureInputModeListButton
      )
      .frame(width: self.metrics.sideButtonWidth,
             height: KeyboardChromeMetrics.keyHeight)

      if self.onAlphabeticModeSwitch == nil {
        KeyButton(
          content: .systemImage("trash"),
          fixedWidth: self.metrics.trashWidth,
          fillOnPress: true,
          firesHaptic: true
        ) {
          self.proxy.deleteAll()
        }
      }

      SpaceBarKey(
        useCustomSpaceBar: self.keyboardState.useCustomSpaceBar,
        showsAlphabetIndicator: self.onAlphabeticModeSwitch != nil && self.showsAlphabetIndicator,
        onSpace: {
          if let action = self.onSpaceAction { action() } else { self.proxy.insertSpace() }
          self.onTextEdited?()
        },
        onCursorMove: { self.proxy.adjustTextPosition($0) },
        onVerticalCursorMove: { self.proxy.moveCursorVertically($0) },
        onTrackingBegan: self.onCursorTrackingBegan,
        onTrackingEnded: {
          self.proxy.resetCursorVerticalState()
          self.onCursorTrackingEnded?()
        }
      )

      ForEach(Array(shortcuts.enumerated()), id: \.offset) { index, shortcut in
        SymbolHoldKey(
          symbol: shortcut,
          fixedWidth: (shortcut == ".com" ? 45 : 44).kbScaled,
          column: index,
          columnCount: shortcuts.count
        ) { selected in
          if let action = self.onShortcutAction {
            action(selected)
          } else {
            self.proxy.insertText(selected)
          }
          self.onTextEdited?()
        }
      }

      KeyboardReturnKey(
        appearance: traits.returnAppearance,
        enabled: traits.returnEnabled,
        width: returnWidth
      ) {
        if let action = self.onReturnAction { action() } else { self.proxy.insertText("\n") }
        self.onTextEdited?()
      }
    }
    .padding(.horizontal, (self.keyboardState.effectiveTypingKind == .alphabetic ? 6.67 : 4).kbScaled)
    .padding(.bottom, 4.kbScaled)
    .opacity(self.keyboardState.auxiliaryControlsHidden ? 0 : 1)
    .allowsHitTesting(!self.keyboardState.auxiliaryControlsHidden)
    .animation(.easeOut(duration: 0.22), value: self.keyboardState.auxiliaryControlsHidden)
    }
    .frame(height: KeyboardChromeMetrics.keyHeight + 4.kbScaled)
  }

  /// Native letter keys are narrow, but isolated shortcut buttons retain
  /// 44pt hit areas. On narrow iPhones, omit optional shortcuts rather than
  /// compressing Space or Return below a usable touch width.
  private func visibleShortcuts(_ requested: [String], totalWidth: CGFloat) -> [String] {
    let padding = (self.keyboardState.effectiveTypingKind == .alphabetic ? 6.67 : 4).kbScaled
    let leading = self.metrics.trashWidth + self.metrics.sideButtonWidth
    let gap = KeyboardChromeMetrics.buttonSpacing
    for count in stride(from: requested.count, through: 0, by: -1) {
      let selected: [String]
      if count == 2 && requested.count == 3 && requested.last == ".com" {
        selected = [requested[0], requested[2]]
      } else {
        selected = Array(requested.prefix(count))
      }
      let shortcutWidths = selected.reduce(CGFloat(0)) { total, key in
        total + (key == ".com" ? 45 : 44).kbScaled
      }
      let returnWidth = count > 0 ? 78.kbScaled : self.metrics.returnWidth
      let gapCount = CGFloat(3 + selected.count)
      let required = 2 * padding + leading + shortcutWidths + returnWidth
        + gapCount * gap + 75.kbScaled
      if required <= totalWidth { return selected }
    }
    return []
  }
}

@MainActor
enum KeyboardActions {

  static func tapLLM(state: KeyboardState, proxy: KeyboardProxy) {
    guard !state.isDictationLocked else {
      self.openUnlock(proxy: proxy)
      return
    }
    withAnimation { state.showLLMActions.toggle() }
  }

  static func longPressLLM(state: KeyboardState, proxy: KeyboardProxy) {
    guard !state.isDictationLocked else {
      self.openUnlock(proxy: proxy)
      return
    }
    let resolved = state.longPressLLMAction.resolve(
      defaultAction: .rewrite,
      customPrompts: state.llmCustomPrompts,
      disabledActions: state.disabledLLMActions,
    )
    if let resolved {
      proxy.requestLLMProcessing(resolved.action, resolved.customPromptId)
    } else {
      state.showLLMActions = true
    }
  }

  private static func openUnlock(proxy: KeyboardProxy) {
    guard let url = DeepLink.unlockURL else { return }
    proxy.openURL(url)
  }
}
