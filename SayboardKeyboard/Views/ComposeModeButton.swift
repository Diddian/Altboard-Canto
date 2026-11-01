import SwiftUI

struct ComposeModeButton: View {
  @ObservedObject var keyboardState: KeyboardState
  var compact = false

  var body: some View {
    Button {
      self.keyboardState.toggleComposeMode()
    } label: {
      VStack(spacing: 1) {
        Image(systemName: self.keyboardState.isComposeMode ? "pencil.and.scribble" : "pencil.line")
          .font(.system(size: (self.compact ? 15 : 17).kbScaled))
        Text(self.keyboardState.isComposeMode ? "WRITE" : "DICT")
          .font(.system(size: 8.kbScaled, weight: .bold, design: .rounded))
      }
      .foregroundStyle(self.keyboardState.isComposeMode ? Color.accentColor : Color.primary)
      .frame(width: (self.compact ? 42 : 45).kbScaled, height: 45.kbScaled)
      .background {
        RoundedRectangle(cornerRadius: 8.5.kbScaled)
          .fill(self.keyboardState.isComposeMode ? Color.accentColor.opacity(0.15) : Color(.keyBackground))
      }
    }
    .disabled(self.keyboardState.isRecording || self.keyboardState.isProcessing)
    .accessibilityLabel(self.keyboardState.isComposeMode ? "Voice Compose on, tap for normal dictation" : "Normal dictation, tap to compose spoken writing")
  }
}
