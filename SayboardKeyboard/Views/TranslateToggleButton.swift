import SwiftUI
import UIKit

private struct TranslateKeyStyle: ButtonStyle {
  let fixedWidth: CGFloat
  let isActive: Bool
  var shape = KeyShape.rounded
  var pressedBinding: Binding<Bool>?

  func makeBody(configuration: Configuration) -> some View {
    let pressed = configuration.isPressed
    let fill = self.isActive
      ? Color.accentColor.opacity(pressed ? 0.2 : 0.12)
      : Color(pressed ? .keyPressedBackground : .keyBackground)
    return configuration.label
      .frame(width: self.fixedWidth, height: 45.kbScaled)
      .keyBackground(shape: self.shape, fill: fill, isPressed: pressed)
      .animation(.easeOut(duration: 0.12), value: self.isActive)
      .onChange(of: configuration.isPressed) { _, down in
        self.pressedBinding?.wrappedValue = down
      }
  }
}

struct TranslateToggleButton: View {
  let fixedWidth: CGFloat
  var shape = KeyShape.rounded
  var compactStyle = false

  @ObservedObject var keyboardState: KeyboardState
  var onHiddenSettings: (() -> Void)? = nil

  @AppStorage(SharedKey.voiceOutputTarget, store: AppGroup.sharedDefaults ?? .standard)
  private var targetRawValue = VoiceOutputTarget.original.rawValue
  @AppStorage(SharedKey.voiceCustomLanguage, store: AppGroup.sharedDefaults ?? .standard)
  private var customLanguage = ""

  @State private var isPressed = false
  @State private var lastSettingsHold: Date?

  private var target: VoiceOutputTarget {
    VoiceOutputTarget(rawValue: self.targetRawValue) ?? .original
  }

  private var currentLabel: String {
    self.target.abbreviatedLabel(customLanguage: self.customLanguage)
  }

  var body: some View {
    Button {
      if let held = self.lastSettingsHold, Date().timeIntervalSince(held) < 0.65 {
        return
      }
      let next = PreferredVoiceLanguages.next(
        target: self.target,
        custom: self.customLanguage,
        preferred: SharedSettings().preferredSpokenLanguages
      )
      self.customLanguage = next.languageCode
      self.targetRawValue = next.target.rawValue
      SharedSettings().isTranslationMode = false
      if self.keyboardState.isRecording || self.keyboardState.isProcessing {
        FeatureDiagnostics.record(.voiceOutput, .selected)
      }
    } label: {
      VStack(spacing: 0) {
        Image(systemName: "translate")
          .font(.system(size: 17.kbScaled))
        Text(verbatim: self.currentLabel)
          .font(.system(size: 8.kbScaled, weight: .bold, design: .rounded))
      }
      .foregroundStyle(self.target == .original ? Color.primary : Color.accentColor)
    }
    .buttonStyle(TranslateKeyStyle(
      fixedWidth: self.fixedWidth,
      isActive: self.target != .original,
      shape: self.shape,
      pressedBinding: self.$isPressed
    ))
    .onChange(of: self.isPressed) { _, down in
      if down { KeyboardHaptics.key() }
    }
    .simultaneousGesture(
      LongPressGesture(minimumDuration: 0.7).onEnded { _ in
        guard let openSettings = self.onHiddenSettings else { return }
        self.lastSettingsHold = Date()
        KeyboardHaptics.key()
        openSettings()
      }
    )
    .accessibilityLabel("Dictation output: \(self.currentLabel). Tap to change language.")
  }
}
