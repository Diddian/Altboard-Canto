import SwiftUI
import UIKit

extension UIColor {
  static let keyBackground = KeyboardPalette.keyFill

  static let keyPressedBackground = KeyboardPalette.pressedFill
}

extension View {
  func keyPressTransition(isPressed: Bool) -> some View {
    self.transaction(value: isPressed) { transaction in
      transaction.animation = isPressed ? nil : .easeOut(duration: 0.02)
    }
  }
}

enum KeyShape {
  case pill
  case rounded
}

extension View {
  @MainActor
  func keyBackground(shape: KeyShape, fill: Color, isPressed: Bool) -> some View {
    self.background {
      Group {
        switch shape {
        case .pill:
          Capsule(style: .continuous).fill(fill)
        case .rounded:
          RoundedRectangle(cornerRadius: KeyboardChromeMetrics.keyCornerRadius, style: .continuous).fill(fill)
        }
      }
      .keyPressTransition(isPressed: isPressed)
    }
  }
}

struct KeyboardProxy {
  let insertText: (String) -> Void
  let documentContextBeforeInput: () -> String?
  let insertSpace: () -> Void
  let deleteBackward: () -> Void
  let deleteWordBackward: () -> Void
  let deleteAll: () -> Void
  let advanceToNextInputMode: () -> Void
  let openURL: (URL) -> Void
  let startDictation: () -> Void
  let stopDictation: () -> Void
  let cancelDictation: () -> Void
  let resolveHost: () -> Void
  let requestLLMProcessing: (LLMAction, UUID?) -> Void
  let requestLLMClipboard: () -> Void
  let adjustTextPosition: (Int) -> Void
  let moveCursorVertically: (Int) -> Void
  let resetCursorVerticalState: () -> Void
  let undoLLM: () -> Void
  let redoLLM: () -> Void
  let setActionBarVisible: (Bool) -> Void
}

enum SetupBlocker {
  case sharedContainerUnavailable
  case fullAccessMissing
  case micDenied
  case noModel
  case modelRemovedByUpdate

  var icon: String {
    switch self {
    case .sharedContainerUnavailable: "externaldrive.badge.exclamationmark"
    case .fullAccessMissing: "lock.open"
    case .micDenied: "mic.slash"
    case .noModel, .modelRemovedByUpdate: "arrow.down.circle"
    }
  }

  var message: LocalizedStringKey {
    switch self {
    case .sharedContainerUnavailable: "Shared keyboard storage is unavailable. Open Altboard Setup diagnostics to check signing"
    case .fullAccessMissing: "Full Access is disabled. Open the Altboard app for setup instructions"
    case .micDenied: "Microphone is disabled. Allow Altboard microphone access to recognize your speech"
    case .noModel: "No speech model yet. Download a speech model to start using voice input"
    case .modelRemovedByUpdate: "Parakeet v3 was updated. Open Altboard to download it again"
    }
  }

  var buttonTitle: LocalizedStringKey {
    switch self {
    case .sharedContainerUnavailable: "Open Altboard"
    case .fullAccessMissing: "Open Settings"
    case .micDenied: "Open Settings"
    case .noModel, .modelRemovedByUpdate: "Open Models"
    }
  }

  var linkURL: URL? {
    switch self {
    case .sharedContainerUnavailable: DeepLink.settingsURL
    case .fullAccessMissing: nil
    case .micDenied: DeepLink.setupMicURL
    case .noModel, .modelRemovedByUpdate: DeepLink.modelsURL
    }
  }
}

struct RectKeyStyle: ButtonStyle {
  var fixedWidth: CGFloat?
  var shape = KeyShape.rounded
  var pressEffect = true
  var fillOnPress = false
  var pressedBinding: Binding<Bool>?
  var visualOverride = false

  func makeBody(configuration: Configuration) -> some View {
    let showPressed = (configuration.isPressed || self.visualOverride) && self.pressEffect
    let fill = Color(showPressed ? .keyPressedBackground : .keyBackground)
    return configuration.label
      .symbolVariant(self.fillOnPress && configuration.isPressed ? .fill : .none)
      .contentTransition(.identity)
      .transaction(value: configuration.isPressed) { $0.animation = nil }
      .foregroundStyle(.primary)
      .frame(maxWidth: self.fixedWidth ?? .infinity)
      .frame(width: self.fixedWidth, height: KeyboardChromeMetrics.keyHeight)
      .keyBackground(shape: self.shape, fill: fill, isPressed: showPressed)
      .onChange(of: configuration.isPressed) { _, new in
        self.pressedBinding?.wrappedValue = new
      }
  }
}

struct KeyboardView: View {

  let proxy: KeyboardProxy

  @ObservedObject var keyboardState: KeyboardState
  @StateObject private var sensoryPulse = KeyboardSensoryPulse.shared

  var body: some View {
    Group {
      if !self.keyboardState.requiresBasicTypingFallback,
         let error = self.keyboardState.llmError {
        LLMErrorPrompt(
          error: error, keyboardState: self.keyboardState,
          onUseClipboard: { self.proxy.requestLLMClipboard() }
        )
        .onAppear {
          FeatureDiagnostics.record(.keyboardRender, .llmPromptMounted)
        }
      } else {
        // A single source of truth for the visible layout. The alphabetic
        // fallback no longer mounts a competing copy of the same keyboard.
        Group {
          switch self.keyboardState.effectiveTypingKind {
          case .standard:
            StandardKeyboardLayout(proxy: self.proxy, keyboardState: self.keyboardState)
          case .extended:
            ExtendedKeyboardLayout(proxy: self.proxy, keyboardState: self.keyboardState)
          case .alphabetic:
            AlphabeticKeyboardLayout(proxy: self.proxy, keyboardState: self.keyboardState)
          }
        }
        .padding(
          .top, self.keyboardState.effectiveTypingKind == .extended ? 3.kbScaled : 0
        )
      }
    }
    .transaction { $0.animation = nil }
    .onChange(of: self.keyboardState.showLLMActions) { _, visible in
      self.proxy.setActionBarVisible(visible)
    }
    .onChange(of: self.keyboardState.isRecording) { _, recording in
      if recording { self.keyboardState.showLLMActions = false }
    }
    .onChange(of: self.keyboardState.isLLMProcessing) { _, processing in
      if processing { self.keyboardState.showLLMActions = false }
    }
    .onAppear {
      self.keyboardState.openURLAction = { [openURL] url in openURL(url) }
      KeyboardHaptics.setSensoryViewReady(true, owner: self.keyboardState)
    }
    .onDisappear {
      KeyboardHaptics.setSensoryViewReady(false, owner: self.keyboardState)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .environment(\.keyboardHapticsEnabled, self.keyboardState.keyboardHapticsEnabled)
    .background {
      UnevenRoundedRectangle(
        topLeadingRadius: KeyboardLayoutGeometry.topCornerRadius.kbScaled,
        topTrailingRadius: KeyboardLayoutGeometry.topCornerRadius.kbScaled,
        style: .continuous
      )
      .fill(Color(uiColor: KeyboardPalette.backdrop))
      .ignoresSafeArea(edges: .bottom)
    }
    .sensoryFeedback(trigger: self.sensoryPulse.count) { _, _ in
      self.keyboardState.keyboardHapticsEnabled ? .selection : nil
    }
  }

  @Environment(\.openURL) private var openURL

  private var activeBlocker: SetupBlocker? {
    if AppGroup.containerURL == nil {
      .sharedContainerUnavailable
    } else if !self.keyboardState.hasFullAccess {
      .fullAccessMissing
    } else if !self.keyboardState.isMicrophoneAuthorized {
      .micDenied
    } else if !self.keyboardState.hasUsableModel {
      self.keyboardState.parakeetV3NeedsRedownload ? .modelRemovedByUpdate : .noModel
    } else {
      nil
    }
  }
}



