
import SwiftUI

struct DictationOutcomeLabel: View {

  let outcome: DictationOutcome
  let onDismiss: () -> Void

  var body: some View {
    self.labelText
      .multilineTextAlignment(.center)
      .fixedSize(horizontal: false, vertical: true)
      .font(.subheadline.weight(.semibold))
      .foregroundStyle(.secondary)
      .padding(.horizontal, 12.kbScaled)
      .padding(.top, 4.kbScaled)
      .padding(.bottom, 8.kbScaled)
      .task(id: self.outcome) {
        try? await Task.sleep(for: Self.visibleDuration)
        guard !Task.isCancelled else { return }
        self.onDismiss()
      }
  }

  private static let visibleDuration = Duration.seconds(4)

  private var labelText: Text {
    let text = Text(self.message)
    guard self.outcome != .noSpeech else { return text }
    return Text(verbatim: "\u{26A0}\u{FE0F} ") + text
  }

  private var message: LocalizedStringKey {
    switch self.outcome {
    case .noSpeech: "No speech recognized. Try speaking again"
    case .engineFailed: "Dictation failed. Try a different speech model in Altboard"
    case .processingFailed: "Translation failed. Original speech saved in Altboard history"
    case .activationFailed: "Microphone did not start. Open Altboard to check mic permission"
    case .unexpectedLanguage: "Speech model detected a language outside your preferences. No text inserted; adjust Voice Output languages or try again"
    }
  }
}
