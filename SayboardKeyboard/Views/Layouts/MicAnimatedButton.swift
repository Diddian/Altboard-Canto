import SwiftUI
import UIKit

struct MicSizing {
  let buttonWidth: CGFloat
  let buttonHeight: CGFloat
  let cornerRadius: CGFloat
  let labelWidth: CGFloat
  let labelHeight: CGFloat
  let spinnerSize: CGFloat
  let waveformScale: CGFloat
  let pulseRingSpacing: CGFloat
}

extension MicSizing {
  @MainActor
  static var standard: MicSizing {
    let diameter = KeyboardMetrics.standardMicDiameter.kbScaled
    return MicSizing(
      buttonWidth: diameter,
      buttonHeight: diameter,
      cornerRadius: diameter / 2,
      labelWidth: 51.kbScaled,
      labelHeight: 39.kbScaled,
      spinnerSize: 39.kbScaled,
      waveformScale: 1,
      pulseRingSpacing: 19.kbScaled
    )
  }

  /// A fixed iOS-style microphone pill for Alphabet's toolbar. No pulse
  /// rings extend above the input view or overlap the host text field.
  @MainActor
  static var alphabet: MicSizing {
    MicSizing(
      buttonWidth: 86.kbScaled,
      buttonHeight: KeyboardChromeMetrics.keyHeight,
      cornerRadius: KeyboardChromeMetrics.keyHeight / 2,
      labelWidth: 33.kbScaled,
      labelHeight: 27.kbScaled,
      spinnerSize: 28.kbScaled,
      waveformScale: 0.78,
      pulseRingSpacing: 8.kbScaled
    )
  }

  /// Identical dimensions and continuous-rounded corner to SpaceBarKey.
  @MainActor
  static func compact(spaceBarWidth: CGFloat) -> MicSizing {
    MicSizing(
      buttonWidth: spaceBarWidth,
      buttonHeight: KeyboardChromeMetrics.keyHeight,
      cornerRadius: KeyboardChromeMetrics.keyCornerRadius,
      labelWidth: 34.kbScaled,
      labelHeight: 28.kbScaled,
      spinnerSize: 28.kbScaled,
      waveformScale: 0.78,
      pulseRingSpacing: 8.kbScaled
    )
  }

  @MainActor
  static func extended(width: CGFloat) -> MicSizing {
    let micScale: CGFloat = 74.0 / 106.0
    let contentScale = micScale * 0.82
    return MicSizing(
      buttonWidth: width,
      buttonHeight: KeyboardChromeMetrics.keyHeight,
      cornerRadius: KeyboardChromeMetrics.keyHeight / 2,
      labelWidth: 56.kbScaled * contentScale,
      labelHeight: 42.kbScaled * contentScale,
      spinnerSize: 42.kbScaled * contentScale,
      waveformScale: contentScale,
      pulseRingSpacing: 24.kbScaled * micScale,
    )
  }
}

struct MicAnimatedButton: View {

  let sizing: MicSizing
  let proxy: KeyboardProxy

  @ObservedObject var keyboardState: KeyboardState

  var body: some View {
    Button(action: self.handleButtonAction) {
      self.micButtonLabel
    }
    .buttonStyle(MicButtonStyle(
      width: self.sizing.buttonWidth,
      height: self.sizing.buttonHeight,
      cornerRadius: self.sizing.cornerRadius,
      pressedBinding: self.$isPressed,
    ))
    .onChange(of: self.isPressed) { _, isDown in
      self.handleMicPressChange(isDown: isDown)
    }
    .onDisappear {
      self.holdActivationTask?.cancel()
      self.holdActivationTask = nil
      if self.holdStartedRecording {
        self.requestHeldStop()
      }
      self.pressPolicy.cancel()
      self.holdStartedRecording = false
      self.suppressButtonAction = false
    }
    // A stuck inference must never disable the only microphone control.
    // During processing it becomes an explicit, token-scoped Cancel action.
    .accessibilityLabel(self.keyboardState.isProcessing
      ? "Cancel dictation processing" : "Dictation microphone")
    .accessibilityHint(self.keyboardState.isProcessing
      ? "Stop pending recognition so the microphone can be used again." : "")
    .onChange(of: self.keyboardState.isRecording, self.handleRecordingChanged)
    .task(id: self.keyboardState.isProcessing, self.observeProcessing)
    .task(id: self.keyboardState.isStartingRecording) {
      guard self.keyboardState.isStartingRecording else { return }
      do { try await Task.sleep(for: .seconds(8)) } catch { return }
      guard self.keyboardState.isStartingRecording else { return }
      self.keyboardState.isStartingRecording = false
      self.keyboardState.dictationOutcome = .activationFailed
    }
  }

  private static let spinnerDelay = Duration.milliseconds(600)

  @State private var isPressed = false
  @State private var pressPolicy = MicrophonePressPolicy()
  @State private var holdActivationTask: Task<Void, Never>?
  @State private var holdStartedRecording = false
  @State private var suppressButtonAction = false
  @State private var lastStartTapAt: Date?
  @State private var showSpinner = false
  @State private var isMorphing = false
  @State private var isSpinnerMorphing = false
  @State private var spinnerMorphCanStep = false
  @State private var pendingSpinnerMorph = false
  @State private var morphDirection = MicMorphAnimation.Direction.toWave
  @State private var recordingStartCount = 0
  @State private var recordingStopCount = 0

  @ViewBuilder
  private var micButtonLabel: some View {
    let shouldShowWave = self.keyboardState.isRecording
    let isLoading = self.keyboardState.isModelLoading && !self.keyboardState.isRecording
    let isSpin = self.showSpinner || self.keyboardState.isStartingRecording
      || (isLoading && !self.isSpinnerMorphing && !self.pendingSpinnerMorph)
    let compactStatus = self.keyboardState.keyboardKind == .standard
      && KeyboardMetrics.isCompactStandard
      && !self.keyboardState.isRecording
      && (self.keyboardState.isProcessing || self.keyboardState.isStartingRecording
        || self.keyboardState.dictationOutcome != nil
        || self.keyboardState.finalOutputPreview != nil)
    let isIdle = !shouldShowWave && !isSpin && !self.isMorphing && !self.isSpinnerMorphing
      && !self.pendingSpinnerMorph
    ZStack {
      MicMorphShape(frameIndex: 0)
        .fill(.primary)
        .frame(width: self.sizing.labelWidth, height: self.sizing.labelHeight)
        .opacity(isIdle && !compactStatus ? 1 : 0)
        .transaction { $0.animation = nil }

      if self.isMorphing {
        MicMorphAnimation(direction: self.morphDirection, onComplete: self.handleMicMorphComplete)
          .frame(width: self.sizing.labelWidth, height: self.sizing.labelHeight)
          .transition(.identity)
      }

      if self.isSpinnerMorphing {
        SpinnerMorphAnimation(canStep: self.spinnerMorphCanStep) {
          self.isSpinnerMorphing = false
          self.spinnerMorphCanStep = false
        }
        .frame(width: self.sizing.labelWidth, height: self.sizing.labelHeight)
        .transition(.identity)
      }

      WaveformBars(levels: self.keyboardState.recentAudioLevels, scale: self.sizing.waveformScale)
        .opacity(
          shouldShowWave && !isSpin && !self.isMorphing
            && !self.isSpinnerMorphing && !self.pendingSpinnerMorph ? 1 : 0
        )

      self.spinnerView(isSpin: isSpin && !compactStatus)
      if compactStatus {
        KeyboardStatusStrip(keyboardState: self.keyboardState, compact: true)
          .padding(.horizontal, 10)
          .frame(width: self.sizing.buttonWidth - 20, height: self.sizing.buttonHeight)
          .transition(.opacity)
      }
    }
  }

  private func handleButtonAction() {
    // A Button action fires only for an accepted tap, not a cancelled touch.
    // It can run before or after SwiftUI reports the finger-up transition.
    if self.pressPolicy.isActive {
      self.holdActivationTask?.cancel()
      self.holdActivationTask = nil
      let action = self.pressPolicy.release(at: Date().timeIntervalSinceReferenceDate)
      self.dispatchRelease(action, buttonActivated: true)
      return
    }
    if self.suppressButtonAction {
      self.suppressButtonAction = false
      return
    }
    self.handleTap()  // VoiceOver / keyboard activation without a touch-down.
  }

  private func handleMicPressChange(isDown: Bool) {
    if self.keyboardState.isProcessing { return }
    if isDown {
      KeyboardHaptics.key()
      // Keep native Button semantics for accepted taps and VoiceOver.
      // The pressed-state transition handles long-hold release/cancellation.
      self.suppressButtonAction = false
      let initial: MicrophonePressPolicy.InitialState
      if self.keyboardState.isDictationLocked {
        initial = .locked
      } else if self.keyboardState.isRecording {
        initial = .recording
      } else if self.keyboardState.isStartingRecording {
        initial = .starting
      } else {
        initial = .idle
      }
      guard self.pressPolicy.begin(
        at: Date().timeIntervalSinceReferenceDate, state: initial
      ) else { return }
      self.holdActivationTask?.cancel()
      if initial == .idle {
        self.holdActivationTask = Task { @MainActor in
          do { try await Task.sleep(for: .milliseconds(280)) } catch { return }
          guard !Task.isCancelled, self.isPressed,
                self.pressPolicy.activateHold(
                  at: Date().timeIntervalSinceReferenceDate
                ) else { return }
          self.holdStartedRecording = true
          self.handleTap()
        }
      }
      return
    }

    self.holdActivationTask?.cancel()
    self.holdActivationTask = nil
    let action = self.pressPolicy.release(at: Date().timeIntervalSinceReferenceDate)
    self.dispatchRelease(action, buttonActivated: false)
  }

  private func dispatchRelease(
    _ action: MicrophonePressPolicy.ReleaseAction, buttonActivated: Bool
  ) {
    switch action {
    case .stop:
      self.suppressButtonAction = true
      self.holdStartedRecording = false
      self.requestHeldStop()
    case .startThenStop:
      self.suppressButtonAction = true
      self.holdStartedRecording = true
      self.handleTap()
      self.requestHeldStop()
      self.holdStartedRecording = false
    case .tap:
      self.holdStartedRecording = false
      // A cancelled/dragged-off press must not start audio. Only the Button's
      // actual action (or VoiceOver activation) confirms a normal tap.
      if buttonActivated { self.handleTap() }
    case .none:
      self.holdStartedRecording = false
    }
  }

  private func requestHeldStop() {
    // Request final transcription, never cancellation. If recording has not
    // yet been acknowledged, the app consumes this token-scoped stop intent
    // once capture begins. No duplicate capture engine is created.
    let settings = SharedSettings()
    settings.synchronize()
    let hasToken = MicrophoneHoldStopIntent.request(
      for: settings.dictationSessionToken, defaults: settings.defaults
    )
    if hasToken || self.keyboardState.isRecording {
      // Always notify the main app, even before the keyboard receives its
      // recording acknowledgement. The service defers an early stop until
      // capture starts, and an already-recording session stops at once.
      self.proxy.stopDictation()
    } else {
      self.keyboardState.isStartingRecording = false
    }
    self.lastStartTapAt = nil
  }

  private func handleTap() {
    if self.keyboardState.isProcessing {
      self.lastStartTapAt = nil
      self.showSpinner = false
      self.proxy.cancelDictation()
      return
    }
    self.keyboardState.clearFinalOutputPreview()
    self.keyboardState.dismissMicHint()
    if self.keyboardState.isRecording {
      // A second quick tap cancels an accidental capture. A later tap
      // remains the normal Stop & Transcribe action.
      if let tapAt = self.lastStartTapAt, Date().timeIntervalSince(tapAt) < 1.3 {
        self.lastStartTapAt = nil
        self.proxy.cancelDictation()
      } else {
        self.proxy.stopDictation()
      }
    } else if self.keyboardState.isStartingRecording {
      self.lastStartTapAt = nil
      self.keyboardState.isStartingRecording = false
      self.proxy.cancelDictation()
    } else if self.keyboardState.isDictationLocked {
      if let url = DeepLink.unlockURL { self.proxy.openURL(url) }
    } else {
      let settings = SharedSettings()
      settings.synchronize()
      let direct = DictationRequestPolicy.shouldRequestWarmSession(
        keyboardActive: self.keyboardState.isSessionActive,
        appActive: settings.isSessionActive,
        heartbeat: settings.mainAppHeartbeat,
        now: CFAbsoluteTimeGetCurrent(),
        practiceFocused: HistoryKeyboardTestSession.isFocused
      )
      if direct {
        // The keyboard may be a new UIKit instance while the app's audio
        // session is still alive. Recheck shared state on every mic tap.
        self.keyboardState.isStartingRecording = true
        self.lastStartTapAt = Date()
        MicrophoneHoldStopIntent.clear(defaults: settings.defaults)
        self.proxy.startDictation()
      } else if let url = DeepLink.dictateURL {
        self.keyboardState.isStartingRecording = true
        self.lastStartTapAt = Date()
        MicrophoneHoldStopIntent.clear(defaults: settings.defaults)
        if OperatingSystem.isHostBundleIdBroken {
          self.proxy.resolveHost()
        }
        settings.dictationCancellationRequested = false
        settings.keyboardRequestedDictationAt = CFAbsoluteTimeGetCurrent()
        settings.keyboardRequestedDictation = true
        settings.dictationSessionToken = UUID().uuidString
        if let token = settings.dictationSessionToken {
          LiveDictationLatency.begin(token: token)
        }
        settings.synchronize()
        self.proxy.openURL(url)
      }
    }
  }

  private func handleRecordingChanged(oldValue: Bool, isRecording: Bool) {
    if isRecording, !oldValue {
      self.recordingStartCount &+= 1
    } else if !isRecording, oldValue {
      self.recordingStopCount &+= 1
    }
    if isRecording, !oldValue, !self.isMorphing {
      self.morphDirection = .toWave
      self.isMorphing = true
    } else if
      !isRecording, oldValue, !self.isMorphing, !self.showSpinner, !self.isSpinnerMorphing,
      !self.pendingSpinnerMorph
    {
      self.morphDirection = .toMic
      self.isMorphing = true
    }
  }

  private func observeProcessing() async {
    let isProcessing = self.keyboardState.isProcessing
    if isProcessing {
      do {
        try await Task.sleep(for: Self.spinnerDelay)
      } catch {
        return
      }
      self.showSpinner = true
    } else {
      if self.showSpinner {
        self.pendingSpinnerMorph = true
      }
      self.showSpinner = false
    }
  }

  private func spinnerView(isSpin: Bool) -> some View {
    TwoDotOrbitProcessing(size: self.sizing.spinnerSize)
      .scaleEffect(isSpin ? 1 : 0.01)
      .transaction(value: isSpin) { transaction in
        transaction.animation = .easeOut(duration: 0.2)
        if !isSpin {
          transaction.addAnimationCompletion {
            if self.pendingSpinnerMorph {
              self.pendingSpinnerMorph = false
              self.isSpinnerMorphing = true
              self.spinnerMorphCanStep = true
            }
          }
        }
      }
  }

  private func handleMicMorphComplete() {
    let wantWave = self.keyboardState.isRecording
    self.isMorphing = false
    if self.morphDirection == .toWave, !wantWave {
      self.morphDirection = .toMic
      self.isMorphing = true
    } else if self.morphDirection == .toMic, wantWave {
      self.morphDirection = .toWave
      self.isMorphing = true
    }
  }
}

struct MicButtonWithPulse: View {

  let sizing: MicSizing
  let proxy: KeyboardProxy
  var reservesPulseSpace = true

  @ObservedObject var keyboardState: KeyboardState

  var body: some View {
    let pulse = PulseRings(
      buttonWidth: self.sizing.buttonWidth,
      buttonHeight: self.sizing.buttonHeight,
      cornerRadius: self.sizing.cornerRadius,
      ringSpacing: self.sizing.pulseRingSpacing,
    )
    let showPulseRings = self.keyboardState.keyboardKind == .standard
      && !KeyboardMetrics.isCompactStandard
      && self.keyboardState.isRecording && !self.keyboardState.isProcessing
    if self.reservesPulseSpace {
      ZStack {
        self.decoratedPulse(pulse: pulse, show: showPulseRings)
        self.micButton
      }
      .frame(minHeight: pulse.maxHeight)
    } else {
      self.micButton.overlay {
        self.decoratedPulse(pulse: pulse, show: showPulseRings)
      }
    }
  }

  private var micButton: some View {
    MicAnimatedButton(sizing: self.sizing, proxy: self.proxy, keyboardState: self.keyboardState)
      .overlay(alignment: .leading) {
        if self.keyboardState.showsMicHint {
          MicHintArrow()
            .alignmentGuide(.leading) { $0[.trailing] + MicHintArrow.gap }
            .transition(.asymmetric(insertion: .identity, removal: .opacity))
        }
      }
  }

  private func decoratedPulse(pulse: PulseRings, show: Bool) -> some View {
    pulse
      .opacity(show ? 1 : 0)
      .scaleEffect(show ? 1 : 0.69)
      .animation(.easeOut(duration: 0.4), value: show)
      .allowsHitTesting(false)
  }
}

struct MicButtonStyle: ButtonStyle {
  let width: CGFloat
  let height: CGFloat
  let cornerRadius: CGFloat
  var pressedBinding: Binding<Bool>?

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .foregroundStyle(.primary)
      .frame(width: self.width, height: self.height)
      .background {
        RoundedRectangle(cornerRadius: self.cornerRadius, style: .continuous)
          .fill(Color(configuration.isPressed ? .keyPressedBackground : .keyBackground))
      }
      .onChange(of: configuration.isPressed) { _, pressed in
        self.pressedBinding?.wrappedValue = pressed
      }
  }
}


// Two balanced points exchange positions around a shared centre.
// This is purely visual: it never owns recording or cancellation state.
private struct TwoDotOrbitProcessing: View {
  let size: CGFloat
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    TimelineView(.animation(minimumInterval: 1.0 / 25.0, paused: self.reduceMotion)) { timeline in
      let angle = timeline.date.timeIntervalSinceReferenceDate * (2 * Double.pi / 1.35)
      let radius = self.size * 0.24
      let dot = self.size * 0.23
      Canvas { context, extent in
        let origin = CGPoint(x: extent.width / 2, y: extent.height / 2)
        for offset in [0.0, Double.pi] {
          let phase = self.reduceMotion ? offset : angle + offset
          let rect = CGRect(
            x: origin.x + radius * cos(phase) - dot / 2,
            y: origin.y + radius * sin(phase) - dot / 2,
            width: dot, height: dot
          )
          context.fill(Path(ellipseIn: rect), with: .foreground)
        }
      }
    }
    .frame(width: self.size, height: self.size)
    .accessibilityHidden(true)
    .allowsHitTesting(false)
  }
}
