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
  @Published private(set) var keyboardProbeTimestamp: TimeInterval = 0
  @Published private(set) var keyboardReportedFullAccess: Bool?
  @Published private(set) var keyboardReportedGroupAvailable: Bool?
  @Published private(set) var audioInputTestResult = "Not tested"
  @Published private(set) var mainGroupTestResult = "Not tested"

  static func hasFullAccessSync() -> Bool {
    guard AppGroup.containerURL != nil else { return false }
    let settings = SharedSettings()
    settings.synchronize()
    return settings.defaults.double(forKey: SharedKey.keyboardProbeTimestamp) > 0
      && settings.defaults.bool(forKey: SharedKey.keyboardProbeFullAccess)
      && settings.defaults.bool(forKey: SharedKey.keyboardProbeGroupAvailable)
  }

  static func isKeyboardAddedSync() -> Bool {
    let keyboards = UserDefaults.standard.stringArray(forKey: "AppleKeyboards") ?? []
    let settings = SharedSettings()
    settings.synchronize()
    if AppGroup.containerURL != nil
      && (settings.defaults.double(forKey: SharedKey.keyboardProbeTimestamp) > 0
        || settings.defaults.bool(forKey: "canto.keyboardOpenedAtLeastOnce"))
    {
      return true
    }
    let installedIdentifiers = Self.installedExtensionIdentifiers()
    return keyboards.contains { entry in
      installedIdentifiers.contains { id in
        entry == id || entry.hasPrefix(id + "@")
      }
    }
  }

  private static func installedExtensionIdentifiers() -> Set<String> {
    var ids: Set<String> = ["app.sayboard.keyboard"]
    if let bundleID = Bundle.main.bundleIdentifier {
      ids.insert(bundleID + ".keyboard")
    }
    if let plugIns = Bundle.main.builtInPlugInsURL,
       let urls = try? FileManager.default.contentsOfDirectory(at: plugIns, includingPropertiesForKeys: nil) {
      for url in urls where url.pathExtension == "appex" {
        if let id = Bundle(url: url)?.bundleIdentifier {
          ids.insert(id)
        }
      }
    }
    return ids
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
    self.hasFullAccess = AppGroup.containerURL != nil
      && self.keyboardReportedFullAccess == true
      && self.keyboardReportedGroupAvailable == true
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
