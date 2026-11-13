import CoreHaptics
import SwiftUI
import UIKit

/// One trigger shared by the main app's previews and the keyboard extension.
/// Each process has its own SwiftUI view and its own pulse counter.
@MainActor
final class KeyboardSensoryPulse: ObservableObject {
  static let shared = KeyboardSensoryPulse()

  @Published private(set) var count = 0

  func trigger() { self.count &+= 1 }
}

/// Public Core Haptics engine cached per process, not created on every key.
/// If iOS denies the engine in the keyboard extension, callers fall back to
/// the original Altboard's SwiftUI sensoryFeedback path.
@MainActor
private enum KeyboardCoreHaptic {
  private static var engine: CHHapticEngine?
  private static var player: (any CHHapticPatternPlayer)?
  private static var playerIntensity: Float?
  private static var unavailableError: String?
  private static var generation: UInt64 = 0

  static func reset() {
    self.generation &+= 1
    self.engine?.stop(completionHandler: nil)
    self.engine = nil
    self.player = nil
    self.playerIntensity = nil
    self.unavailableError = nil
  }

  /// Prepare the engine and pattern before any key is pressed. Startup is
  /// considerably more expensive than playing an already-compiled transient.
  static func prewarm(strength: Double) {
    guard engine == nil, unavailableError == nil,
          CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
    do {
      let newEngine = try CHHapticEngine()
      newEngine.playsHapticsOnly = true
      newEngine.isAutoShutdownEnabled = true
      self.generation &+= 1
      let generation = self.generation
      newEngine.resetHandler = {
        Task { @MainActor in
          guard generation == self.generation else { return }
          self.reset()
        }
      }
      try newEngine.start()
      engine = newEngine
      let intensity = Float(max(0.15, min(1.0, strength)))
      let event = CHHapticEvent(
        eventType: .hapticTransient,
        parameters: [
          CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
          CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.52)
        ],
        relativeTime: 0
      )
      let pattern = try CHHapticPattern(events: [event], parameters: [])
      player = try newEngine.makePlayer(with: pattern)
      playerIntensity = intensity
    } catch {
      // Failure must not retry expensive engine startup on first key-down.
      // Surface a bounded code so play() uses the existing sensory fallback.
      let ns = error as NSError
      unavailableError = "engine-prewarm-failed:\(ns.domain):\(ns.code)"
      engine = nil
      player = nil
      playerIntensity = nil
    }
  }

  static func play(strength: Double) -> String? {
    if let unavailableError { return unavailableError }
    guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
      return "hardware-unavailable"
    }

    do {
      if engine == nil {
        let newEngine = try CHHapticEngine()
        newEngine.playsHapticsOnly = true
        newEngine.isAutoShutdownEnabled = true
        self.generation &+= 1
        let generation = self.generation
        newEngine.resetHandler = {
          Task { @MainActor in
            guard generation == self.generation else { return }
            self.reset()
          }
        }
        try newEngine.start()
        engine = newEngine
      }
      guard let engine else { return "engine-missing" }
      let intensity = Float(max(0.15, min(1.0, strength)))
      if player == nil || playerIntensity != intensity {
        let event = CHHapticEvent(
          eventType: .hapticTransient,
          parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.52)
          ],
          relativeTime: 0
        )
        let pattern = try CHHapticPattern(events: [event], parameters: [])
        player = try engine.makePlayer(with: pattern)
        playerIntensity = intensity
      }
      try player?.start(atTime: 0)
      return nil
    } catch {
      // One retry if iOS stopped the engine after keyboard handoff.
      if let engine {
        do {
          try engine.start()
          try player?.start(atTime: 0)
          return nil
        } catch let retryError {
          self.engine = nil
          self.player = nil
          self.playerIntensity = nil
          let ns = retryError as NSError
          let detail = "engine-start-failed:\(ns.domain):\(ns.code)"
          self.unavailableError = detail
          return detail
        }
      }
      let ns = error as NSError
      let detail = "engine-creation-failed:\(ns.domain):\(ns.code)"
      self.unavailableError = detail
      return detail
    }
  }
}

/// The keyboard's standard output is Core Haptics rather than UIKit.
/// UIKit remains available as a diagnostic comparison on iOS versions where
/// Core Haptics works but UIFeedbackGenerator is silent.
@MainActor
enum KeyboardHaptics {
  enum Technique: String, CaseIterable {
    case automatic, core, sensory, selection, soft, light, medium, heavy
    var displayName: String { self.rawValue.capitalized }
  }

  private static let selection = UISelectionFeedbackGenerator()
  private static let soft = UIImpactFeedbackGenerator(style: .soft)
  private static let light = UIImpactFeedbackGenerator(style: .light)
  private static let medium = UIImpactFeedbackGenerator(style: .medium)
  private static let heavy = UIImpactFeedbackGenerator(style: .heavy)
  private static var prepared = false
  private static var activeOwner: ObjectIdentifier?
  private static var sensoryViewOwner: ObjectIdentifier?

  /// The SwiftUI path is safe only while its active keyboard is mounted.
  static func setSensoryViewReady(_ ready: Bool, owner: AnyObject) {
    let id = ObjectIdentifier(owner)
    if ready { sensoryViewOwner = id }
    else if sensoryViewOwner == id { sensoryViewOwner = nil }
  }

  static func key(
    strength override: Double? = nil,
    enabled overrideEnabled: Bool? = nil,
    technique: Technique = .automatic,
    playsSound: Bool = true
  ) {
    // iOS honors Keyboard Feedback > Sound independently of haptics.
    if playsSound { UIDevice.current.playInputClick() }
    let settings = SharedSettings()
    let enabled = overrideEnabled ?? settings.keyboardHapticsEnabled
    let strength = min(1.0, max(0.15, override ?? settings.keyboardHapticStrength))
    guard enabled else {
      KeyboardHapticTrace.record(technique: technique.rawValue, enabled: false,
        fullAccess: settings.hasFullAccess, outcome: "disabled")
      return
    }

    let driver: KeyboardHapticDriver? = switch technique {
    case .automatic: settings.keyboardHapticDriver
    case .core: .coreHaptics
    case .sensory: .sensoryFeedback
    default: nil
    }
    if let driver {
      switch driver {
      case .coreHaptics:
        if let error = KeyboardCoreHaptic.play(strength: strength) {
          // The extension can reject Core Haptics after an app/keyboard
          // handoff. Use a direct UIKit pulse instead of a SwiftUI state
          // update that may not render while the keyboard is rebuilding.
          if sensoryViewOwner != nil &&
              error.hasPrefix("engine-prewarm-failed:com.apple.CoreHaptics") {
            // Core Haptics is denied. Use one mounted SwiftUI pulse; never
            // submit both UIKit and SwiftUI feedback on the same key.
            KeyboardSensoryPulse.shared.trigger()
            KeyboardHapticTrace.record(technique: "core->sensory", enabled: true,
              fullAccess: settings.hasFullAccess, outcome: error)
          } else {
            triggerUIKit(technique: .automatic, strength: strength)
            KeyboardHapticTrace.record(technique: "core->uikit", enabled: true,
              fullAccess: settings.hasFullAccess, outcome: error)
          }
        } else {
          KeyboardHapticTrace.record(technique: "core", enabled: true,
            fullAccess: settings.hasFullAccess, outcome: "submitted")
        }
      case .sensoryFeedback:
        KeyboardSensoryPulse.shared.trigger()
        KeyboardHapticTrace.record(technique: "swiftui", enabled: true,
          fullAccess: settings.hasFullAccess, outcome: "triggered")
      case .uiKit:
        triggerUIKit(technique: .automatic, strength: strength)
        KeyboardHapticTrace.record(technique: "uikit", enabled: true,
          fullAccess: settings.hasFullAccess, outcome: "submitted")
      }
    } else {
      triggerUIKit(technique: technique, strength: strength)
      KeyboardHapticTrace.record(technique: technique.rawValue, enabled: true,
        fullAccess: settings.hasFullAccess, outcome: "submitted")
    }
  }

  private static func triggerUIKit(technique: Technique, strength: Double) {
    let resolved: Technique = if technique == .automatic {
      switch strength {
      case ..<0.30: .selection
      case ..<0.45: .soft
      case ..<0.70: .light
      case ..<0.85: .medium
      default: .heavy
      }
    } else {
      technique
    }
    if resolved == .selection {
      selection.selectionChanged()
      selection.prepare()
    } else {
      let generator: UIImpactFeedbackGenerator = switch resolved {
      case .soft: soft
      case .light: light
      case .medium: medium
      case .heavy: heavy
      case .automatic, .core, .sensory, .selection: light
      }
      generator.impactOccurred()
      generator.prepare()
    }
  }

  static func suspend(owner: AnyObject? = nil) {
    // UIKit may overlap the old and new keyboard controllers. Do not let
    // the disappearing controller shut down the new controller's engine.
    if let owner, let activeOwner, activeOwner != ObjectIdentifier(owner) { return }
    guard prepared else { return }
    prepared = false
    activeOwner = nil
    KeyboardCoreHaptic.reset()
    FeatureDiagnostics.record(.haptics, .stopped)
  }

  static func prepare(owner: AnyObject? = nil) {
    let settings = SharedSettings()
    guard settings.keyboardHapticsEnabled else {
      if prepared { suspend() } else { KeyboardCoreHaptic.reset() }
      return
    }
    if let owner { activeOwner = ObjectIdentifier(owner) }
    // viewWillAppear and foreground callbacks may both run for one keyboard.
    // Prepare once per appearance, not repeatedly on the touch path.
    guard !prepared else { return }
    prepared = true
    FeatureDiagnostics.record(.haptics, .started)
    if settings.keyboardHapticDriver == .coreHaptics {
      KeyboardCoreHaptic.prewarm(strength: settings.keyboardHapticStrength)
    }
    selection.prepare()
    soft.prepare()
    light.prepare()
    medium.prepare()
    heavy.prepare()
  }
}

