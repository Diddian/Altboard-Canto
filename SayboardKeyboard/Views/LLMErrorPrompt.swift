
import SwiftUI

enum LLMError {
  case noTextBeforeCursor
  case selectText
  case clipboardUnavailable
  case storageUnavailable
  case translationTargetRequired

  var icon: String {
    switch self {
    case .noTextBeforeCursor, .selectText: "character.cursor.ibeam"
    case .clipboardUnavailable: "doc.on.clipboard"
    case .storageUnavailable, .translationTargetRequired: "exclamationmark.triangle"
    }
  }

  var message: LocalizedStringKey {
    switch self {
    case .noTextBeforeCursor:
      "To use AI actions, make sure the text field has text and the cursor is after it"
    case .selectText:
      "Select text to rewrite, then tap AI again. If selection is unavailable, copy the text and choose Use Clipboard."
    case .clipboardUnavailable:
      "Clipboard text is unavailable. Copy the text first and retry."
    case .translationTargetRequired:
      "Choose an output language with the Output key, then select Translate again."
    case .storageUnavailable:
      "AI shared storage is unavailable. Enable Full Access and reopen Altboard."
    }
  }

  var buttonTitle: LocalizedStringKey {
    switch self {
    case .noTextBeforeCursor, .selectText, .clipboardUnavailable, .storageUnavailable, .translationTargetRequired: "OK"
    }
  }
}

struct LLMErrorPrompt: View {

  let error: LLMError

  @ObservedObject var keyboardState: KeyboardState
  var onUseClipboard: (() -> Void)? = nil

  var body: some View {
    VStack(spacing: 12.kbScaled) {
      Image(systemName: self.error.icon)
        .font(.system(size: 40.kbScaled))
        .foregroundStyle(.blue)

      Text(self.error.message)
        .font(.subheadline.weight(.semibold))
        .multilineTextAlignment(.center)
        .padding(.horizontal, 32.kbScaled)

      Button {
        withAnimation(.easeOut(duration: 0.12)) { self.keyboardState.llmError = nil }
      } label: {
        Text(self.error.buttonTitle)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.white)
          .padding(.horizontal, 20.kbScaled)
          .frame(minHeight: 40.kbScaled)
          .background(.blue, in: Capsule())
      }
      .padding(.horizontal, 32.kbScaled)
      if case .selectText = self.error, let useClipboard = self.onUseClipboard {
        Button("Use Clipboard") { useClipboard() }
          .font(.subheadline.weight(.medium))
          .foregroundStyle(.blue)
          .frame(minHeight: 36.kbScaled)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

