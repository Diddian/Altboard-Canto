import SwiftUI

extension KeyboardState {
  var showsAIButton: Bool {
    self.llmEnabled && self.hasUsableLLMModel
  }

}

struct KeyboardChromeMetrics {

  @MainActor
  init(keyboardState: KeyboardState) {
    let compact = keyboardState.selectedVariantSupportsTranslation || keyboardState.showsAIButton
    let side: CGFloat = (compact ? 43 : 45).kbScaled
    let wide: CGFloat = 92.kbScaled
    let showsGlobe = true // Reserve leading Emoji key.

    self.sideButtonWidth = side
    self.showsGlobe = showsGlobe
    self.trashWidth = showsGlobe ? side : wide
    self.returnWidth = showsGlobe ? (side + Self.buttonSpacing + side) : wide
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

  var body: some View {
    HStack(spacing: KeyboardChromeMetrics.buttonSpacing) {
      KeyButton(
        content: .systemImage("face.smiling"),
        fixedWidth: self.metrics.sideButtonWidth
      ) {
        self.keyboardState.showsEmojiPicker = true
      }
      .onLongPressGesture(minimumDuration: 0.55) {
        if self.keyboardState.needsInputModeSwitchKey {
          self.proxy.advanceToNextInputMode()
        }
      }

      KeyButton(
        content: .systemImage("trash"),
        fixedWidth: self.metrics.trashWidth,
        fillOnPress: true,
        firesHaptic: false,
      ) {
        self.proxy.deleteAll()
      }

      SpaceBarKey(
        useCustomSpaceBar: self.keyboardState.useCustomSpaceBar,
        onSpace: { self.proxy.insertSpace() },
        onCursorMove: { self.proxy.adjustTextPosition($0) },
      )

      KeyButton(content: .systemImage("return.left"), fixedWidth: self.metrics.returnWidth) {
        self.proxy.insertText("\n")
      }
    }
    .padding(.horizontal, 4.kbScaled)
    .padding(.bottom, 4.kbScaled)
    .opacity(self.keyboardState.auxiliaryControlsHidden ? 0 : 1)
    .allowsHitTesting(!self.keyboardState.auxiliaryControlsHidden)
    .animation(.easeOut(duration: 0.22), value: self.keyboardState.auxiliaryControlsHidden)
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
