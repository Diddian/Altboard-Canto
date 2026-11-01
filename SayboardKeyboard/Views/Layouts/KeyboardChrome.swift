import SwiftUI

extension KeyboardState {
  var showsAIButton: Bool {
    self.llmEnabled && self.hasUsableLLMModel
  }

  var showsGlobeButton: Bool {
    self.needsInputModeSwitchKey || self.showGlobeKey
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

struct KeyboardStatusStrip: View {

  @ObservedObject var keyboardState: KeyboardState

  let onContentHeightChange: (CGFloat) -> Void

  var body: some View {
    Color.clear
      .overlay(alignment: .top) {
        Group {
          if self.keyboardState.isProcessing {
            VoiceProcessingStatusView(progress: self.keyboardState.voiceProcessingProgress)
              .transition(.opacity)
          } else if self.keyboardState.isStartingRecording && !self.keyboardState.isRecording {
            Text("Activating microphone…")
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(.secondary)
              .padding(.vertical, 6.kbScaled)
          } else if self.showModelLoading {
            ModelLoadingLabel(
              isLoading: self.keyboardState.isModelLoading,
              lowStorage: self.keyboardState.isLowDiskSpace,
              isFirstUse: !self.keyboardState.hasPreparedModelOnce,
              rebuildsAfterUpdates: self.keyboardState.selectedVariantSpecializesForNeuralEngine,
            )
            .transition(.opacity)
          } else if let outcome = self.keyboardState.dictationOutcome {
            DictationOutcomeLabel(outcome: outcome) {
              self.keyboardState.dictationOutcome = nil
            }
            .transition(.opacity)
          } else if self.keyboardState.isDictationLocked {
            DictationLockedLabel()
              .transition(.opacity)
          }
        }
        .animation(.easeOut(duration: 0.3), value: self.keyboardState.isStartingRecording)
        .animation(.easeOut(duration: 0.3), value: self.keyboardState.isModelLoading)
        .animation(.easeOut(duration: 0.3), value: self.keyboardState.isLowDiskSpace)
        .animation(.easeOut(duration: 0.3), value: self.keyboardState.dictationOutcome)
        .animation(.easeOut(duration: 0.3), value: self.keyboardState.isDictationLocked)
        .background {
          GeometryReader { geo in
            Color.clear
              .onAppear { self.onContentHeightChange(geo.size.height) }
              .onChange(of: geo.size.height) { _, height in
                self.onContentHeightChange(height)
              }
          }
        }
      }
  }

  private var showModelLoading: Bool {
    self.keyboardState.isModelLoading && self.keyboardState.isProcessing
  }
}

/// A low-contrast status below the keyboard. Elapsed seconds are real, not a
/// fabricated ONNX loading percentage; ASR text appears before cleanup.
private struct VoiceProcessingStatusView: View {
  let progress: VoiceProcessingProgress?

  var body: some View {
    VStack(alignment: .leading, spacing: 4.kbScaled) {
      HStack(spacing: 6.kbScaled) {
        ProgressView()
          .controlSize(.mini)
        TimelineView(.periodic(from: .now, by: 1)) { context in
          let elapsed = max(0, Int(context.date.timeIntervalSinceReferenceDate
            - (self.progress?.startedAt ?? context.date.timeIntervalSinceReferenceDate)))
          Text("\(self.stageTitle) · \(elapsed)s elapsed")
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
      if let preview = self.progress?.rawPreview, !preview.isEmpty {
        Text("Recognized: \(preview)")
          .font(.caption2)
          .foregroundStyle(.tertiary)
          .lineLimit(2)
          .truncationMode(.tail)
          .accessibilityLabel("Raw speech transcript: \(preview)")
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 13.kbScaled)
    .padding(.vertical, 7.kbScaled)
  }

  private var stageTitle: String {
    guard let progress else { return "Processing recording" }
    if progress.stage == .loadingRecognizer {
      return "Loading \(SharedSettings().selectedVariant.displayName)"
    }
    return progress.stage.title
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
