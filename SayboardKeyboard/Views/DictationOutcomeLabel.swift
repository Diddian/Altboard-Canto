
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
    let text: Text = switch self.outcome {
    case .noSpeech: Text("No speech detected")
    case .engineFailed: Text("Recognition failed")
    case .processingFailed: Text("Translation failed")
    case .activationFailed: Text("Mic activation failed")
    case .sessionRequired: Text("Enable Active Session in Altboard Settings.", tableName: "VoiceSession")
    case .unexpectedLanguage: Text("Unexpected language")
    }
    guard self.outcome != .noSpeech else { return text }
    return Text(verbatim: "\u{26A0}\u{FE0F} ") + text
  }
}
