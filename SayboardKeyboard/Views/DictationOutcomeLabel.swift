
import SwiftUI

struct DictationOutcomeLabel: View {

  let outcome: DictationOutcome
  let onDismiss: () -> Void

  var body: some View {
    self.labelText
      .multilineTextAlignment(.center)
      .lineLimit(2)
      .minimumScaleFactor(0.75)
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
    case .noSpeech: "No speech detected"
    case .engineFailed: "Recognition failed"
    case .processingFailed: "Translation failed"
    case .activationFailed: "Mic activation failed"
    case .unexpectedLanguage: "Unexpected language"
    }
  }
}
