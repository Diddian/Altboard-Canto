import Accelerate
@preconcurrency import AVFoundation
import os
import UIKit

private struct TapState: @unchecked Sendable {
  let accumulator: AudioBufferAccumulator
  let recorder: AudioRecorder
  let converter: AVAudioConverter?
  let targetFormat: AVAudioFormat
}

enum UnifiedCaptureOwner: String, Sendable {
  case dictation, meeting, conversation
}

enum AudioSessionError: LocalizedError {
  case noInputChannels
  case tapInstallFailed(String)
  case audioConversionUnavailable
  case alreadyCapturing

  var errorDescription: String? {
    switch self {
    case .alreadyCapturing:
      "Another voice recording is already using the microphone."
    case .noInputChannels:
      "No audio input available. Microphone access may be restricted."
    case .tapInstallFailed(let reason):
      "Audio tap failed: \(reason)"
    case .audioConversionUnavailable:
      "The microphone audio format is unavailable. Reconnect the microphone and try again."
    }
  }
}

@MainActor
final class BackgroundAudioSession: ObservableObject {

  private static weak var activeSession: BackgroundAudioSession?
  private static var playbackOwner: UUID?
  private static var stopPlayback: (@MainActor () -> Void)?

  static func configurePlayback(owner: UUID, stop: @escaping @MainActor () -> Void) -> Bool {
    guard self.activeSession?.captureOwner == nil else {
      FeatureDiagnostics.record(.speechAudio, .blocked)
      return false
    }
    if self.playbackOwner != owner { self.stopPlayback?() }
    self.playbackOwner = owner
    self.stopPlayback = stop
    guard self.activeSession?.isSessionHealthy != true else { return true }
    do {
      let audio = AVAudioSession.sharedInstance()
      try audio.setCategory(.playback, mode: .default)
      try audio.setActive(true)
      return true
    } catch {
      self.releasePlayback(owner: owner)
      FeatureDiagnostics.record(.speechAudio, .failed)
      return false
    }
  }

  static func releasePlayback(owner: UUID) {
    guard self.playbackOwner == owner else { return }
    self.playbackOwner = nil
    self.stopPlayback = nil
  }

  @Published private(set) var isSessionActive = false
  @Published private(set) var captureOwner: UnifiedCaptureOwner?
  private(set) var hasRecordedThisSession = false
  // One temporary owner while cold Qwen releases audio for final decoding.
  private var recoveryGate = AudioSessionRecoveryGate()

  var onInterruptionBegan: (() -> Void)?

  var onSessionEnded: (() -> Void)?

  let audioEngine = AVAudioEngine()

  var isSessionHealthy: Bool {
    self.isSessionActive && self.audioEngine.isRunning && Self.activeSession === self
  }

  func captureConfirmation(
    owner: UnifiedCaptureOwner, elapsed: TimeInterval = 0
  ) -> DictationCapturePolicy.Confirmation {
    DictationCapturePolicy.confirmation(
      sessionHealthy: self.isSessionHealthy,
      ownsCapture: self.captureOwner == owner,
      outputFrames: self.tapDiagnostics.withLock { $0.outputFrames },
      elapsed: elapsed
    )
  }

  nonisolated let levelBridge = AudioLevelBridge(mode: .writer)

  nonisolated let tapDiagnostics = OSAllocatedUnfairLock<TapDiagnostics>(initialState: TapDiagnostics())

  func startSession() throws {
    self.recoveryGate.cancel()
    if self.isSessionActive {
      guard !self.isSessionHealthy else { return }
      guard self.captureOwner == nil else { throw AudioSessionError.alreadyCapturing }
      // A stale flag is not proof of a running audio engine.
      self.endSession()
    }
    DictationBreadcrumb.record("audio: startSession entered")
    FeatureDiagnostics.record(.voiceSession, .started)
    self.settings.mainAppHeartbeat = 0
    self.lastHeartbeatTime.withLock { $0 = 0 }
    let audioSession = AVAudioSession.sharedInstance()
    var sessionActivated = false
    var tapAttempted = false
    do {
      try audioSession.setCategory(
        .playAndRecord,
        mode: .default,
        options: [.mixWithOthers, .defaultToSpeaker, .allowBluetoothA2DP],
      )
      try audioSession.setAllowHapticsAndSystemSoundsDuringRecording(true)
      DictationBreadcrumb.record("audio: activating AVAudioSession")
      try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
      sessionActivated = true
      DictationBreadcrumb.record("audio: installing persistent input tap")
      tapAttempted = true
      try self.installPersistentTap()
      DictationBreadcrumb.record("audio: starting AVAudioEngine")
      self.audioEngine.prepare()
      try self.audioEngine.start()
      DictationBreadcrumb.record("audio: AVAudioEngine started")
    } catch {
      if self.audioEngine.isRunning { self.audioEngine.stop() }
      if tapAttempted { self.audioEngine.inputNode.removeTap(onBus: 0) }
      self.tapState.withLock { $0 = nil }
      if sessionActivated {
        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
      }
      self.settings.isSessionActive = false
      FeatureDiagnostics.record(.voiceSession, .failed)
      DictationBreadcrumb.record("audio: session activation failed; resources released")
      throw error
    }
    Self.activeSession = self
    self.isSessionActive = true
    self.settings.isSessionActive = true
    TranscriptionBridge.postDarwinNotification(DarwinNotificationName.sessionStarted)

    self.setupInterruptionObserver()
    self.resetInactivityTimer()
  }

  func endSession() {
    let wasParked = self.recoveryGate.isParked
    self.recoveryGate.cancel()
    if wasParked && !self.isSessionActive {
      self.finishParkedSession()
      return
    }
    self.closeActiveSession(notifyEnded: true)
  }

  private func finishParkedSession() {
    self.onSessionEnded?()
    TranscriptionBridge.postDarwinNotification(DarwinNotificationName.sessionEnded)
    if let observer = self.interruptionObserver {
      NotificationCenter.default.removeObserver(observer)
      self.interruptionObserver = nil
    }
  }

  /// A model-loading pause releases the engine without declaring user Stop.
  private func closeActiveSession(notifyEnded: Bool) {
    guard self.isSessionActive else { return }
    self.deactivateTap()
    self.resetLevelState()
    if notifyEnded { self.onSessionEnded?() }

    self.inactivityTimer?.invalidate()
    self.inactivityTimer = nil
    if self.audioEngine.isRunning { self.audioEngine.stop() }
    self.audioEngine.inputNode.removeTap(onBus: 0)
    try? AVAudioSession.sharedInstance().setActive(
      false, options: .notifyOthersOnDeactivation
    )

    if Self.activeSession === self { Self.activeSession = nil }
    self.isSessionActive = false
    self.settings.isSessionActive = false
    self.settings.mainAppHeartbeat = 0
    self.idleCountdown.reset()
    self.wasCountingIdle = false
    FeatureDiagnostics.record(.voiceSession, .stopped)
    if notifyEnded {
      TranscriptionBridge.postDarwinNotification(DarwinNotificationName.sessionEnded)
    }
    self.hasRecordedThisSession = false

    if notifyEnded, let observer = self.interruptionObserver {
      NotificationCenter.default.removeObserver(observer)
      self.interruptionObserver = nil
    }
  }

  /// Park the previously armed session exactly once during cold-model loading.
  @discardableResult
  func suspendForModelLoad() -> Bool {
    guard self.recoveryGate.park(
      sessionActive: self.isSessionActive, capturing: self.captureOwner != nil
    ) else { return false }
    self.closeActiveSession(notifyEnded: false)
    return true
  }

  /// A manual Stop, cancellation, interruption or another audio owner wins.
  /// nil: no pending intent; false: restart failed; true: restored.
  func restoreAfterModelLoad(allowed: Bool) -> Bool? {
    guard let permitted = self.recoveryGate.take(
      allowed: allowed,
      captureFree: self.captureOwner == nil,
      playbackFree: Self.playbackOwner == nil,
      competingSessionFree: Self.activeSession == nil || Self.activeSession === self
    ) else { return nil }
    guard permitted else {
      self.finishParkedSession()
      return nil
    }
    if self.isSessionHealthy { return true }
    do {
      try self.startSession()
      return self.isSessionHealthy
    } catch {
      self.finishParkedSession()
      return false
    }
  }

  /// Single capture gate shared by keyboard dictation and Meetings.
  /// Only the owner that acquired the tap may release it.
  func beginCapture(
    owner: UnifiedCaptureOwner, accumulator: AudioBufferAccumulator, recorder: AudioRecorder
  ) throws {
    guard self.captureOwner == nil else {
      FeatureDiagnostics.record(.speechAudio, .blocked)
      throw AudioSessionError.alreadyCapturing
    }
    Self.stopPlayback?()
    Self.stopPlayback = nil
    Self.playbackOwner = nil
    try self.activateTap(accumulator: accumulator, recorder: recorder)
    self.captureOwner = owner
    FeatureDiagnostics.record(.speechAudio, .started)
  }

  func endCapture(owner: UnifiedCaptureOwner) {
    guard self.captureOwner == owner else { return }
    self.deactivateTap()
  }

  private func activateTap(accumulator: AudioBufferAccumulator, recorder: AudioRecorder) throws {
    let inputNode = self.audioEngine.inputNode
    let hwFormat = inputNode.outputFormat(forBus: 0)

    guard
      let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: AudioBufferMath.targetSampleRate,
        channels: 1,
        interleaved: false,
      )
    else {
      throw AudioSessionError.audioConversionUnavailable
    }

    let needsConversion = hwFormat.sampleRate != AudioBufferMath.targetSampleRate || hwFormat.channelCount != 1
    let converter: AVAudioConverter? = needsConversion
      ? AVAudioConverter(from: hwFormat, to: targetFormat)
      : nil

    guard !needsConversion || converter != nil else {
      throw AudioSessionError.audioConversionUnavailable
    }
    DiagnosticLog.write(
      "activateTap: hw=\(hwFormat.sampleRate)Hz/\(hwFormat.channelCount)ch "
        + "needsConversion=\(needsConversion) converter=\(converter != nil)"
    )
    self.tapDiagnostics.withLock { $0 = TapDiagnostics() }

    self.tapState.withLock {
      $0 = TapState(
        accumulator: accumulator,
        recorder: recorder,
        converter: converter,
        targetFormat: targetFormat,
      )
    }
    self.hasRecordedThisSession = true
    self.cancelInactivityTimer()
  }

  func deactivateTap() {
    self.tapState.withLock { $0 = nil }
    self.captureOwner = nil
    self.resetLevelState()
    self.logTapDiagnostics()
    self.resetInactivityTimer()
  }

  func updateTimeout() {
    let isCapturing = self.tapState.withLock { $0 != nil }
    guard !isCapturing else { return }
    self.resetInactivityTimer()
  }

  func setHostForeground(_ foreground: Bool) {
    guard self.hostIsForeground != foreground else { return }
    self.hostIsForeground = foreground
    self.reconcileInactivity()
  }

  func keyboardActivityDidChange() {
    self.settings.synchronize()
    self.reconcileInactivity()
  }

  private let settings = SharedSettings()
  private nonisolated let tapState = OSAllocatedUnfairLock<TapState?>(initialState: nil)
  private var inactivityTimer: Timer?
  private var idleCountdown = VoiceSessionPolicy.IdleTimer()
  private var wasCountingIdle = false
  private var hostIsForeground = UIApplication.shared.applicationState != .background
  private nonisolated let lastFlushTime = OSAllocatedUnfairLock<CFAbsoluteTime>(initialState: 0)
  private nonisolated let lastHeartbeatTime = OSAllocatedUnfairLock<CFAbsoluteTime>(initialState: 0)
  private nonisolated let previousLevel = OSAllocatedUnfairLock<Float>(initialState: 0)
  private nonisolated let rmsRingBuffer = OSAllocatedUnfairLock<(buffer: [Float], index: Int)>(
    initialState: (buffer: [Float](repeating: 0, count: AudioBufferMath.rmsPreFilterWindowSize), index: 0)
  )
  private var interruptionObserver: NSObjectProtocol?

  private func resetLevelState() {
    self.previousLevel.withLock { $0 = 0 }
    self.rmsRingBuffer.withLock { state in
      state.buffer = [Float](repeating: 0, count: AudioBufferMath.rmsPreFilterWindowSize)
      state.index = 0
    }
    self.levelBridge.writeLevel(0)
    self.levelBridge.flushToDefaults()
  }

  private func cancelInactivityTimer() {
    self.inactivityTimer?.invalidate()
    self.inactivityTimer = nil
    self.idleCountdown.reset()
    if self.wasCountingIdle { FeatureDiagnostics.record(.voiceSession, .idleCancelled) }
    self.wasCountingIdle = false
  }

  private func installPersistentTap() throws {
    let inputNode = self.audioEngine.inputNode
    let hwFormat = inputNode.outputFormat(forBus: 0)

    guard hwFormat.channelCount > 0, hwFormat.sampleRate > 0 else {
      throw AudioSessionError.noInputChannels
    }

    inputNode.removeTap(onBus: 0)

    let state = self.tapState
    let bridge = self.levelBridge
    let lastFlush = self.lastFlushTime
    let lastHeartbeat = self.lastHeartbeatTime
    let prevLevel = self.previousLevel
    let ringBuf = self.rmsRingBuffer
    let diagnostics = self.tapDiagnostics
    try ObjCExceptionCatcher.catchException {
      inputNode.installTap(onBus: 0, bufferSize: 4096, format: nil) { @Sendable buffer, _ in
        let now = CFAbsoluteTimeGetCurrent()
        let heartbeat = lastHeartbeat.withLock { last -> (write: Bool, first: Bool) in
          if now - last >= 0.5 {
            let first = last == 0
            last = now
            return (true, first)
          }
          return (false, false)
        }
        if heartbeat.write {
          AppGroup.sharedDefaults?.set(now, forKey: SharedKey.mainAppHeartbeat)
          if heartbeat.first {
            TranscriptionBridge.postDarwinNotification(DarwinNotificationName.sessionStarted)
          }
        }

        // Deactivation waits for the last callback before finalization drains
        // the FIFO or closes the file. Do not retain capture state past this lock.
        state.withLock { active in
          guard let active else { return }

          let rms = AudioBufferMath.rms(from: buffer)
          let filtered = AudioBufferMath.preFilterRMS(min(rms * 14, 1.0), ringBuffer: ringBuf)
          bridge.writeLevel(AudioBufferMath.smoothLevel(filtered, previous: prevLevel))

          let shouldFlush = lastFlush.withLock { last -> Bool in
            if now - last >= 1.0 / 30.0 {
              last = now
              return true
            }
            return false
          }
          if shouldFlush {
            bridge.flushToDefaults()
          }

          active.recorder.appendBuffer(buffer)

          let samples: [Float] =
            if let converter = active.converter {
              AudioBufferMath.resample(
                buffer,
                converter: converter,
                targetFormat: active.targetFormat,
                diagnostics: diagnostics,
              )
            } else {
              AudioBufferMath.samples(from: buffer)
            }

          if !samples.isEmpty { active.accumulator.append(samples) }

          diagnostics.withLock { diag in
            diag.buffers += 1
            diag.inputFrames += Int(buffer.frameLength)
            diag.outputFrames += samples.count
            if diag.inputSampleRate == 0 {
              diag.inputSampleRate = buffer.format.sampleRate
              diag.inputChannels = buffer.format.channelCount
            }
            if rms > diag.peakRMS { diag.peakRMS = rms }
          }
        }
      }
    }
  }

  private func resetInactivityTimer() {
    self.idleCountdown.reset()
    self.reconcileInactivity()
  }

  private func reconcileInactivity() {
    self.inactivityTimer?.invalidate()
    self.inactivityTimer = nil
    guard self.isSessionActive else {
      self.idleCountdown.reset()
      self.wasCountingIdle = false
      return
    }
    let now = Date().timeIntervalSinceReferenceDate
    let decision = self.idleCountdown.evaluate(
      now: now, timeout: self.settings.sessionAutoStopPolicy.timeoutSeconds,
      appForeground: self.hostIsForeground, capturing: self.captureOwner != nil,
      keyboard: self.settings.voiceKeyboardActivity
    )
    let delay: TimeInterval?
    let countingIdle: Bool
    switch decision {
    case .active(let checkAfter):
      delay = checkAfter
      countingIdle = false
    case .unlimited:
      delay = nil
      countingIdle = false
    case .idle(let deadline):
      delay = max(0.1, deadline - now)
      countingIdle = true
    case .expired:
      FeatureDiagnostics.record(.voiceSession, .timedOut)
      self.endSession()
      return
    }
    if countingIdle != self.wasCountingIdle {
      FeatureDiagnostics.record(.voiceSession, countingIdle ? .idleStarted : .idleCancelled)
      self.wasCountingIdle = countingIdle
    }
    guard let delay else { return }
    self.inactivityTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.settings.synchronize()
        self?.reconcileInactivity()
      }
    }
  }

  private func setupInterruptionObserver() {
    if let observer = self.interruptionObserver {
      NotificationCenter.default.removeObserver(observer)
    }
    self.interruptionObserver = NotificationCenter.default.addObserver(
      forName: AVAudioSession.interruptionNotification,
      object: AVAudioSession.sharedInstance(),
      queue: .main,
    ) { [weak self] notification in
      let userInfo = notification.userInfo
      let typeValue = userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
      let optionsValue = userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
      Task { @MainActor [weak self] in
        self?.handleInterruption(typeValue: typeValue, optionsValue: optionsValue)
      }
    }
  }

  private func handleInterruption(typeValue: UInt?, optionsValue: UInt?) {
    guard
      let typeValue,
      let type = AVAudioSession.InterruptionType(rawValue: typeValue)
    else {
      return
    }

    switch type {
    case .began:
      FeatureDiagnostics.record(.voiceSession, .interrupted)
      if self.recoveryGate.isParked {
        self.endSession()
        return
      }
      self.deactivateTap()
      self.onInterruptionBegan?()

    case .ended:
      let shouldResume = optionsValue.map {
        AVAudioSession.InterruptionOptions(rawValue: $0).contains(.shouldResume)
      } ?? false
      guard shouldResume else {
        self.endSession()
        return
      }
      do {
        try self.audioEngine.start()
        self.resetInactivityTimer()
      } catch {
        self.endSession()
      }

    @unknown default:
      break
    }
  }
}


