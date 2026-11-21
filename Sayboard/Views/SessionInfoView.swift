import SwiftUI

struct SessionInfoView: View {
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        self.explanation(
          "The orange indicator", symbol: "mic.fill",
          body: "The orange dot means iOS microphone input is active. An enabled voice session keeps that input available between dictations."
        )
        self.explanation(
          "When audio is saved", symbol: "waveform",
          body: "While voice is ready, unused microphone buffers are discarded. Recording and transcription start when you press the microphone. Saved recordings follow your History & Storage settings."
        )
        self.explanation(
          "Fewer app switches", symbol: "keyboard",
          body: "Enable a voice session once, then return to your conversation. While the session stays active, you can dictate again from the keyboard. Auto-Stop counts idle time after you leave the app and keyboard."
        )
        self.explanation(
          "Stop the session", symbol: "stop.circle",
          body: "Turn off Active Session to release the microphone. Never disables the idle timeout; it uses more battery while the session is active. Closing the app or an iOS interruption can still end the session."
        )
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding()
    }
    .navigationTitle("Active Session Info")
    .navigationBarTitleDisplayMode(.inline)
  }

  private func explanation(_ title: LocalizedStringKey, symbol: String, body: LocalizedStringKey) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Label { Text(title, tableName: "VoiceSession") } icon: { Image(systemName: symbol) }
        .font(.headline)
      Text(body, tableName: "VoiceSession")
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}
