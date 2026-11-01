import SwiftUI
import UIKit

private struct TranslateKeyStyle: ButtonStyle {
  let fixedWidth: CGFloat
  let isActive: Bool
  var shape = KeyShape.rounded

  func makeBody(configuration: Configuration) -> some View {
    let pressed = configuration.isPressed
    let fill = self.isActive
      ? Color.accentColor.opacity(pressed ? 0.2 : 0.12)
      : Color(pressed ? .keyPressedBackground : .keyBackground)
    return configuration.label
      .frame(width: self.fixedWidth, height: 45.kbScaled)
      .keyBackground(shape: self.shape, fill: fill, isPressed: pressed)
      .animation(.easeOut(duration: 0.12), value: self.isActive)
  }
}

struct TranslateToggleButton: View {
  let fixedWidth: CGFloat
  var shape = KeyShape.rounded
  var compactStyle = false

  @ObservedObject var keyboardState: KeyboardState

  @AppStorage(SharedKey.voiceOutputTarget, store: AppGroup.sharedDefaults ?? .standard)
  private var targetRawValue = VoiceOutputTarget.original.rawValue
  @AppStorage(SharedKey.voiceCustomLanguage, store: AppGroup.sharedDefaults ?? .standard)
  private var customLanguage = ""
  @AppStorage(SharedKey.preferredSpokenLanguages, store: AppGroup.sharedDefaults ?? .standard)
  private var preferredSpokenLanguages = [String]()

  private var target: VoiceOutputTarget {
    VoiceOutputTarget(rawValue: self.targetRawValue) ?? .original
  }

  private var currentLabel: String {
    let code = PreferredVoiceLanguages.currentCode(target: self.target, custom: self.customLanguage)
    return PreferredVoiceLanguages.choices(from: SharedSettings().preferredSpokenLanguages)
      .first(where: { $0.languageCode == code })?.label ?? self.target.keyboardLabel
  }

  var body: some View {
    Button {
      let next = PreferredVoiceLanguages.next(
        target: self.target,
        custom: self.customLanguage,
        preferred: SharedSettings().preferredSpokenLanguages
      )
      self.customLanguage = next.languageCode
      self.targetRawValue = next.target.rawValue
      SharedSettings().isTranslationMode = false
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
      shape: self.shape
    ))
    .accessibilityLabel("Dictation output: \(self.currentLabel). Tap to change language.")
    .gatedSensoryFeedback(.selection, trigger: self.targetRawValue)
  }
}
