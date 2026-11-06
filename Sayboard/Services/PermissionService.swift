import AVFoundation
import UIKit

enum MicrophonePermissionState {
  case undetermined
  case denied
  case granted
}

@MainActor
final class PermissionService: ObservableObject {
  @Published private(set) var microphoneState = MicrophonePermissionState.undetermined
  @Published private(set) var isKeyboardAdded = false
  @Published private(set) var hasFullAccess = false
  @Published private(set) var fullAccessEvidence: KeyboardAccessEvidence = .unknown
  @Published private(set) var keyboardProbeTimestamp: TimeInterval = 0
  @Published private(set) var keyboardReportedFullAccess: Bool?
  @Published private(set) var keyboardReportedGroupAvailable: Bool?
  @Published private(set) var audioInputTestResult = "Not tested"
  @Published private(set) var mainGroupTestResult = "Not tested"

  static func currentFullAccessEvidence() -> KeyboardAccessEvidence {
    guard AppGroup.containerURL != nil else { return .unknown }
    let settings = SharedSettings()
    settings.synchronize()
    let stamp = settings.defaults.double(forKey: SharedKey.keyboardProbeTimestamp)
    return KeyboardAccessEvidence.assess(
      at: stamp, now: CFAbsoluteTimeGetCurrent(),
      fullAccess: stamp > 0 ? settings.defaults.bool(forKey: SharedKey.keyboardProbeFullAccess) : nil,
      extensionGroupAvailable: settings.defaults.bool(forKey: SharedKey.keyboardProbeGroupAvailable),
      appGroupAvailable: true
    )
  }

  static func hasFullAccessSync() -> Bool {
    currentFullAccessEvidence() == .confirmed
  }

  // A recent activation proves the keyboard was used recently, not that
  // it remains installed. No supported host-app API enumerates enabled keyboards.
  static func isKeyboardAddedSync() -> Bool {
    guard AppGroup.containerURL != nil else { return false }
    let settings = SharedSettings()
    settings.synchronize()
    return KeyboardAccessEvidence.isRecentReport(
      at: settings.defaults.double(forKey: SharedKey.keyboardProbeTimestamp),
      now: CFAbsoluteTimeGetCurrent()
    )
  }

  var keyboardInstallationStatus: String {
    self.isKeyboardAdded
      ? "Recently opened (current installation not independently verified)"
      : "Not verified — open Altboard in a text field, then return"
  }

  func refreshAll() {
    self.refreshMicrophoneState()
    self.refreshKeyboardProbe()
    self.refreshKeyboardAdded()
    self.refreshFullAccess()
    self.testMainSharedContainer()
    self.registerFullAccessObserverIfNeeded()
  }

  func refreshMicrophoneState() {
    let permission = AVAudioApplication.shared.recordPermission
    switch permission {
    case .granted: self.microphoneState = .granted
    case .denied: self.microphoneState = .denied
    case .undetermined: self.microphoneState = .undetermined
    @unknown default: self.microphoneState = .denied
    }
    self.settings.isMicrophoneAuthorized = self.microphoneState == .granted
  }

  func requestMicrophonePermission() {
    AVAudioApplication.requestRecordPermission { [weak self] granted in
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.microphoneState = granted ? .granted : .denied
        self.settings.isMicrophoneAuthorized = granted
      }
    }
  }

  func refreshKeyboardAdded() {
    self.isKeyboardAdded = Self.isKeyboardAddedSync()
  }

  func refreshKeyboardProbe() {
    self.settings.synchronize()
    let timestamp = self.settings.defaults.double(forKey: SharedKey.keyboardProbeTimestamp)
    self.keyboardProbeTimestamp = timestamp
    if timestamp > 0 {
      self.keyboardReportedFullAccess = self.settings.defaults.bool(forKey: SharedKey.keyboardProbeFullAccess)
      self.keyboardReportedGroupAvailable = self.settings.defaults.bool(forKey: SharedKey.keyboardProbeGroupAvailable)
    } else {
      self.keyboardReportedFullAccess = nil
      self.keyboardReportedGroupAvailable = nil
    }
  }

  func refreshFullAccess() {
    self.fullAccessEvidence = Self.currentFullAccessEvidence()
    self.hasFullAccess = self.fullAccessEvidence == .confirmed
  }

  func testMainSharedContainer() {
    guard let root = AppGroup.containerURL else {
      self.mainGroupTestResult = "Unavailable — no shared container"
      return
    }
    let path = root.appendingPathComponent("canto-sharing-probe.txt")
    let marker = UUID().uuidString
    do {
      try marker.write(to: path, atomically: true, encoding: .utf8)
      let value = try String(contentsOf: path, encoding: .utf8)
      try? FileManager.default.removeItem(at: path)
      self.mainGroupTestResult = value == marker ? "PASS: read and write OK" : "FAILED: shared data mismatch"
    } catch {
      self.mainGroupTestResult = "FAILED: \(error.localizedDescription)"
    }
  }

  /// Starts the app's audio engine to test hardware permission, without recording speech.
  func testAudioInput(session: BackgroundAudioSession) {
    self.refreshMicrophoneState()
    guard self.microphoneState == .granted else {
      self.audioInputTestResult = "Blocked: iOS microphone permission is not granted"
      return
    }
    if session.isSessionActive {
      self.audioInputTestResult = "Audio session already active"
      return
    }
    do {
      try session.startSession()
      let format = session.audioEngine.inputNode.outputFormat(forBus: 0)
      self.audioInputTestResult = "PASS: audio engine started (\(Int(format.sampleRate)) Hz, \(format.channelCount) ch)"
      session.endSession()
    } catch {
      self.audioInputTestResult = "FAILED: \(error.localizedDescription)"
      if session.isSessionActive { session.endSession() }
    }
  }

  var keyboardProbeSummary: String {
    guard self.keyboardProbeTimestamp > 0 else { return "No report from keyboard extension" }
    let age = max(0, CFAbsoluteTimeGetCurrent() - self.keyboardProbeTimestamp)
    return "Last report \(Int(age)) seconds ago"
  }

  private let settings = SharedSettings()
  private var fullAccessObserver: DarwinNotificationObserver?

  private func registerFullAccessObserverIfNeeded() {
    guard self.fullAccessObserver == nil else { return }
    self.fullAccessObserver = TranscriptionBridge.observeDarwinNotification(
      DarwinNotificationName.fullAccessChanged
    ) { [weak self] in
      DispatchQueue.main.async { self?.refreshAll() }
    }
  }
}
