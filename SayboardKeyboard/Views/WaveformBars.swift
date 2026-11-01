import SwiftUI

/// Scrolling audio-amplitude history from the real microphone tap.
struct WaveformBars: View {
  var levels: [Float]
  var scale: CGFloat = 1.0

  var body: some View {
    let recent = Array(self.levels.suffix(17))
    let isSpeaking = recent.suffix(3).contains { $0 > 0.05 }
    HStack(alignment: .center, spacing: 3 * scale) {
      Circle()
        .fill(isSpeaking ? Color.accentColor : Color.secondary.opacity(0.5))
        .frame(width: 5 * scale, height: 5 * scale)

      HStack(alignment: .center, spacing: 2.1 * scale) {
        ForEach(recent.indices, id: \.self) { index in
          RoundedRectangle(cornerRadius: 1.4 * scale, style: .continuous)
            .fill(.primary)
            .frame(width: 2.4 * scale, height: self.barHeight(recent[index]))
        }
      }
      .frame(height: 30 * scale)
    }
    .animation(.linear(duration: 0.045), value: self.levels)
    .accessibilityLabel(isSpeaking ? "Recording: voice detected" : "Recording: quiet")
  }

  private func barHeight(_ level: Float) -> CGFloat {
    let amplitude = CGFloat(sqrt(max(0, min(1, level))))
    return (3 + 27 * amplitude) * scale
  }
}
