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
    Button(action: self.handleTap) {
      self.micButtonLabel
    }
    .buttonStyle(MicButtonStyle(
      width: self.sizing.buttonWidth,
      height: self.sizing.buttonHeight,
      cornerRadius: self.sizing.cornerRadius,
    ))
    .allowsHitTesting(!self.keyboardState.isProcessing)
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

  private func handleTap() {
    KeyboardHaptics.key()
    self.keyboardState.clearFinalOutputPreview()
    self.keyboardState.dismissMicHint()
    if self.keyboardState.isRecording {
      self.proxy.stopDictation()
    } else if self.keyboardState.isStartingRecording {
      return
    } else if self.keyboardState.isDictationLocked {
      if let url = DeepLink.unlockURL { self.proxy.openURL(url) }
    } else if self.keyboardState.isSessionActive {
      self.keyboardState.isStartingRecording = true
      self.proxy.startDictation()
    } else if let url = DeepLink.dictateURL {
      self.keyboardState.isStartingRecording = true
      let settings = SharedSettings()
      if OperatingSystem.isHostBundleIdBroken {
        self.proxy.resolveHost()
      }
      settings.keyboardRequestedDictationAt = CFAbsoluteTimeGetCurrent()
      settings.keyboardRequestedDictation = true
      settings.dictationSessionToken = UUID().uuidString
      settings.synchronize()
      self.proxy.openURL(url)
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
    MetaballSpinner(color: .primary, size: self.sizing.spinnerSize)
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

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .foregroundStyle(.primary)
      .frame(width: self.width, height: self.height)
      .background {
        RoundedRectangle(cornerRadius: self.cornerRadius, style: .continuous).fill(Color(.keyBackground))
      }
  }
}
