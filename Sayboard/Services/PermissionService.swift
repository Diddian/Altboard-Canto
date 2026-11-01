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

  static func hasFullAccessSync() -> Bool {
    AppGroup.containerURL != nil && SharedSettings().hasFullAccess
  }

  static func isKeyboardAddedSync() -> Bool {
    let keyboards = UserDefaults.standard.stringArray(forKey: "AppleKeyboards") ?? []
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
    self.refreshKeyboardAdded()
    self.refreshFullAccess()
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

  func refreshFullAccess() {
    // Only the real keyboard extension may report hasFullAccess.
    // A newly allocated UIInputViewController is not a meaningful probe.
    self.settings.synchronize()
    self.hasFullAccess = AppGroup.containerURL != nil && self.settings.hasFullAccess
  }

  private let settings = SharedSettings()
  private var fullAccessObserver: DarwinNotificationObserver?

  private func registerFullAccessObserverIfNeeded() {
    guard self.fullAccessObserver == nil else { return }
    self.fullAccessObserver = TranscriptionBridge.observeDarwinNotification(
      DarwinNotificationName.fullAccessChanged
    ) { [weak self] in
      DispatchQueue.main.async { self?.refreshFullAccess() }
    }
  }
}
